// TV: DECISIONS 10 Q4 (path-mapping table, UNC → smb://), 01 §6.6 (Locate… mapping, /Volumes fallback), ARCH §9.4
//     (open / reveal resolution table), 05 §6.9 (web links without a scheme), OC-12 (missing file shows the resolved path).
import Foundation
import Testing
@testable import AACore

@MainActor
@Suite("W-PERSIST path mapping and opener", .serialized)
struct PersistPathMapperTests {
    @Test("Windows path recognition and canonical prefixes")
    func recognition() {
        #expect(PathMapper.isWindowsPath(#"Z:\Manuals\a.pdf"#))
        #expect(PathMapper.isWindowsPath("c:/docs/a.pdf"))
        #expect(PathMapper.isWindowsPath(#"\\srv\share\a.pdf"#))
        #expect(!PathMapper.isWindowsPath("C:foo"))
        #expect(!PathMapper.isWindowsPath("/Volumes/x"))
        #expect(!PathMapper.isWindowsPath("files/a.pdf"))
        #expect(PathMapper.canonicalPrefix("z:/x/") == #"Z:\x"#)
        #expect(PathMapper.canonicalPrefix(#"\\srv\share\"#) == #"\\srv\share"#)
        #expect(PathMapper.isValidPrefix("Z:"))
        #expect(PathMapper.isValidPrefix(#"Z:\Manuals"#))
        #expect(PathMapper.isValidPrefix(#"\\srv\share"#))
        #expect(!PathMapper.isValidPrefix(#"\\srv"#))
        #expect(!PathMapper.isValidPrefix("Manuals"))
    }

    @Test("Longest matching prefix on a component boundary, case-insensitive; the rest is appended")
    func mapping() {
        let m = PathMapper()
        m.mappings = [PathMapping(windowsPrefix: "Z:", macPath: "/Volumes/Ship"),
                      PathMapping(windowsPrefix: #"Z:\Manuals"#, macPath: "/Volumes/Docs"),
                      PathMapping(windowsPrefix: #"\\srv\share"#, macPath: "smb://srv/share")]
        #expect(m.macURL(for: #"z:\Manuals\Pump.pdf"#)?.path == "/Volumes/Docs/Pump.pdf")
        #expect(m.macURL(for: #"Z:\Other\a b.pdf"#)?.path == "/Volumes/Ship/Other/a b.pdf")
        #expect(m.macURL(for: #"Z:\ManualsX\a.pdf"#)?.path == "/Volumes/Ship/ManualsX/a.pdf")
        #expect(m.macURL(for: #"\\SRV\Share\dir\x.pdf"#)?.absoluteString == "smb://srv/share/dir/x.pdf")
        #expect(m.macURL(for: #"\\srv\shareX\x.pdf"#) == nil || m.macURL(for: #"\\srv\shareX\x.pdf"#)?.path.hasPrefix("/Volumes/") == true)
        #expect(m.macURL(for: #"Y:\x.pdf"#) == nil)
    }

    @Test("UNC → smb:// and the share URL")
    func smb() {
        #expect(PathMapper.smbURL(forUNC: #"\\bridge-nas\manuals\Main engine\a.pdf"#)?.absoluteString
                == "smb://bridge-nas/manuals/Main%20engine/a.pdf")
        #expect(PathMapper.smbShareURL(forUNC: #"\\bridge-nas\manuals\x\y.pdf"#)?.absoluteString == "smb://bridge-nas/manuals")
        #expect(PathMapper.smbURL(forUNC: #"Z:\a"#) == nil)
        #expect(PathMapper.smbURL(forUNC: #"\\only-server"#) == nil)
    }

    @Test("Locate… infers the mapping from the shared tail")
    func inferred() {
        let m = PathMapper.inferredMapping(windowsPath: #"Z:\Manuals\Pump.pdf"#,
                                           chosen: URL(fileURLWithPath: "/Volumes/Ship/Manuals/Pump.pdf"))
        #expect(m == PathMapping(windowsPrefix: "Z:", macPath: "/Volumes/Ship"))
        let unc = PathMapper.inferredMapping(windowsPath: #"\\srv\share\a\b.pdf"#,
                                             chosen: URL(fileURLWithPath: "/Users/u/Share/a/b.pdf"))
        #expect(unc == PathMapping(windowsPrefix: #"\\srv\share"#, macPath: "/Users/u/Share"))
        let none = PathMapper.inferredMapping(windowsPath: #"Z:\x\y.pdf"#, chosen: URL(fileURLWithPath: "/tmp/other.pdf"))
        #expect(none == PathMapping(windowsPrefix: #"Z:\x"#, macPath: "/tmp"))
        #expect(PathMapper.inferredMapping(windowsPath: "/posix", chosen: URL(fileURLWithPath: "/x")) == nil)
        let mapper = PathMapper()
        mapper.upsert(PathMapping(windowsPrefix: "z:\\", macPath: " /Volumes/A "))
        mapper.upsert(PathMapping(windowsPrefix: "Z:", macPath: "/Volumes/B"))
        #expect(mapper.mappings == [PathMapping(windowsPrefix: "Z:", macPath: "/Volumes/B")])
    }

    @Test("The table persists per Mac in UserDefaults aa.pathMappings")
    func persistence() {
        let temp = TempDefaults("persist-map"); defer { temp.remove() }
        let prefs = temp.preferences
        let a = PathMapper(preferences: prefs)
        a.mappings = [PathMapping(windowsPrefix: "Z:", macPath: "/Volumes/Ship")]
        let b = PathMapper(preferences: prefs)
        #expect(b.mappings == a.mappings)
        #expect(PathMapper.preferencesKey.rawValue == "aa.pathMappings")
    }

    @Test("Opener resolution table, open / reveal outcomes, web links")
    func opener() throws {
        let made = StoreFactory.make()
        let ds = made.dataStore
        try FileManager.default.createDirectory(at: ds.filesFolder, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: ds.filesFolder.appending(path: "ab12_x.pdf"))
        var opened: [URL] = []
        var revealed: [URL] = []
        let savedOpen = AttachmentOpener.openURL, savedReveal = AttachmentOpener.reveal
        AttachmentOpener.openURL = { opened.append($0); return true }
        AttachmentOpener.reveal = { revealed.append(contentsOf: $0) }
        let mapper = PathMapper()
        mapper.mappings = [PathMapping(windowsPrefix: "Z:", macPath: ds.appFolder.path)]
        AttachmentOpener.mapperOverride = mapper
        defer {
            AttachmentOpener.openURL = savedOpen; AttachmentOpener.reveal = savedReveal; AttachmentOpener.mapperOverride = nil
        }
        let app = ds.appFolder.standardizedFileURL.path
        #expect(AttachmentOpener.url(forStored: "files/ab12_x.pdf", isLink: false, dataStore: ds)?.path == app + "/files/ab12_x.pdf")
        #expect(AttachmentOpener.url(forStored: #"files\ab12_x.pdf"#, isLink: false, dataStore: ds)?.path == app + "/files/ab12_x.pdf")
        #expect(AttachmentOpener.open(stored: "files/ab12_x.pdf", isLink: false, dataStore: ds) == .opened)
        #expect(opened.last?.lastPathComponent == "ab12_x.pdf")
        #expect(AttachmentOpener.open(stored: "files/missing.pdf", isLink: false, dataStore: ds) == .notFound(app + "/files/missing.pdf"))
        #expect(AttachmentOpener.open(stored: #"Z:\files\ab12_x.pdf"#, isLink: false, dataStore: ds) == .opened)
        #expect(AttachmentOpener.open(stored: #"Q:\x.pdf"#, isLink: false, dataStore: ds) == .windowsPathUnmapped(#"Q:\x.pdf"#))
        #expect(AttachmentOpener.open(stored: "https://www.imo.org", isLink: true, dataStore: ds) == .opened)
        #expect(opened.last?.absoluteString == "https://www.imo.org")
        #expect(AttachmentOpener.open(stored: ds.filesFolder.path, isLink: false, dataStore: ds) == .opened)
        #expect(revealed.last?.path == ds.filesFolder.path)
        #expect(AttachmentOpener.revealInFinder(stored: "files/ab12_x.pdf", dataStore: ds) == .opened)
        #expect(AttachmentOpener.revealInFinder(stored: "files/nope.pdf", dataStore: ds) == .notFound(app + "/files/nope.pdf"))
        #expect(AttachmentOpener.revealInFinder(stored: #"Q:\x"#, dataStore: ds) == .windowsPathUnmapped(#"Q:\x"#))
        #expect(PersistOpenerText.missing("/a/b.pdf") == "That file is missing:\n\n/a/b.pdf")
        #expect(PersistOpenerText.unmapped(#"Z:\a.pdf"#) == "This file is on a Windows drive (Z:). Map the drive letter to a folder on this Mac in Settings ▸ File Links.")
    }

    @Test("normalizeWebLink: www./domain → https, x@y → mailto, schemes kept, junk rejected")
    func webLinks() {
        #expect(AttachmentOpener.normalizeWebLink("www.imo.org")?.absoluteString == "https://www.imo.org")
        #expect(AttachmentOpener.normalizeWebLink("imo.org/en")?.absoluteString == "https://imo.org/en")
        #expect(AttachmentOpener.normalizeWebLink("master@ship.com")?.absoluteString == "mailto:master@ship.com")
        #expect(AttachmentOpener.normalizeWebLink("https://x.y/a b") != nil)
        #expect(AttachmentOpener.normalizeWebLink("ftp://h/f")?.scheme == "ftp")
        #expect(AttachmentOpener.normalizeWebLink("  ") == nil)
        #expect(AttachmentOpener.normalizeWebLink("not a link") == nil)
        #expect(PersistOpenerText.hasScheme("mailto:a@b"))
        #expect(!PersistOpenerText.hasScheme(#"C:\x"#))
    }
}
