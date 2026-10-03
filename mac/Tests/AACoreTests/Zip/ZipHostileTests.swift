// TV: 01 §6.7 (any damaged archive throws ZipError — never traps), 01 §6.6 / DATA-041/045 (every non-link
//     data.json path matches a bundle entry byte for byte: entry names are NFC), Stage V round 2 V2-COMPAT findings
//     (crafted Zip64 overflow archives; NFD attachment names; a bundle with two data.json entries).
// Fixtures/zip/hostile/ holds the verifier's crafted archives:
//   crash-locator.zip     Zip64 locator → 0xFFFFFFFFFFFFFFF0 (EOCD counts 0xFFFF)
//   crash-cdoffset.zip    Zip64 EOCD cdSize 1, cdOffset UInt64.max
//   crash-localoffset.zip central entry, Zip64 extra offset 0xFFFFFFFFFFFFFFF0
//   crash-csize.zip       central entry, Zip64 extra usize 5 / csize 0x7FFFFFFFFFFFFFF0, stored
//   dupdata.zip           [data.json "{not json", data.json <valid Windows data>]
//   zip64.zip / backslash.zip  Windows-shaped bundles with the NFC entry files/abc_Café.pdf (Zip64 / `\` names)
import Foundation
import Testing
@testable import AACore

@Suite struct ZipHostileTests {
    static let crafted = ["crash-locator", "crash-cdoffset", "crash-localoffset", "crash-csize"]

    /// Opens, peeks, reads and extracts every entry; every failure must be a thrown ZipError (a trap ends the run).
    private func exercise(_ open: () throws -> ZipReader) {
        guard let r = try? open() else { return }
        let folder = TempFolder("aa-hostile")
        for e in r.entries {
            #expect(throws: ZipError.self) { _ = try r.data(for: e) }
            #expect(throws: ZipError.self) { try r.extract(e, to: folder.file("one")) }
        }
        #expect(throws: ZipError.self) { try r.extractAll(to: folder.url.appending(path: "all")) }
    }

    @Test(arguments: crafted)
    func craftedArchivesThrowInsteadOfTrapping(_ name: String) throws {
        let url = Fixtures.url("zip/hostile/\(name).zip")
        exercise { try ZipReader(url: url) }                                   // file source (import, peeks)
        let bytes = try Data(contentsOf: url)
        exercise { try ZipReader(data: bytes) }                                // memory source (XLSX import)
        // The shared-save / Drive ticks peek without the user doing anything: nil, not a crash.
        #expect(BundleService.peekZipLastModified(url) == nil)
        #expect(BundleService.peekBundleSource(url) == nil)
    }

    @Test func craftedHeadersAreRejectedAtOpen() throws {
        for name in ["crash-locator", "crash-cdoffset"] {
            #expect(throws: ZipError.self) { try ZipReader(url: Fixtures.url("zip/hostile/\(name).zip")) }
        }
    }

    // Built in memory: every size field near the top of its range, for both sources.
    @Test func overflowingSizesAndOffsets() throws {
        let big: [UInt64] = [0xFFFF_FFFF_FFFF_FFFF, 0xFFFF_FFFF_FFFF_FFF0, 0x7FFF_FFFF_FFFF_FFF0, 0x8000_0000_0000_0000,
                             UInt64(Int.max), 1 << 40]
        for v in big {
            for field in 0..<3 {
                for method: UInt16 in [0, 8] {
                    let data = Self.zip64Entry(usize: field == 0 ? v : 5, csize: field == 1 ? v : 5,
                                               offset: field == 2 ? v : 0, method: method)
                    exercise { try ZipReader(data: data) }
                    let folder = TempFolder("aa-hostile-file")
                    let u = try folder.write("h.zip", data)
                    exercise { try ZipReader(url: u) }
                }
            }
        }
    }

    // A Deflate entry claiming a terabyte from 5 bytes is rejected before any allocation.
    @Test func impossibleDeflateRatioIsCorrupt() throws {
        let r = try ZipReader(data: Self.zip64Entry(usize: 1 << 40, csize: 5, offset: 0, method: 8))
        #expect(throws: ZipError.self) { _ = try r.data(for: r.entries[0]) }
        #expect(throws: RawDeflateError.self) { _ = try RawDeflate.inflate([0x03, 0x00], expectedLength: Int.max / 2) }
    }

    // MARK: Duplicate entries (V2-COMPAT: the review previewed the first data.json, the import applied the last)

    @MainActor @Test func duplicateDataJSONIsRefusedBeforeAnythingIsWritten() throws {
        let url = Fixtures.url("zip/hostile/dupdata.zip")
        let r = try ZipReader(url: url)
        #expect(r.entries.map(\.name) == ["data.json", "data.json"])
        #expect(BundleService.peekZipLastModified(url) == nil)                 // the first entry, as on Windows
        let folder = TempFolder("aa-dup")
        #expect(throws: ZipReader.duplicate("data.json")) { try r.extractAll(to: folder.url) }
        #expect(!folder.exists("data.json"))
        // Shared pull and smart import fail cleanly (Windows' ExtractToDirectory throws on the duplicate); the
        // local data is untouched.
        let made = StoreFactory.make()
        let ds = made.dataStore
        try Data("{\"LastModified\":\"2026-01-01T00:00:00\"}".utf8).write(to: ds.defaultDataFile)
        let before = try Data(contentsOf: ds.defaultDataFile)
        #expect(throws: (any Error).self) { _ = try BundleService.importBundleSmart(ds, from: url) }
        #expect(throws: (any Error).self) { try BundleService.importSharedBundle(ds, from: url) }
        #expect(try Data(contentsOf: ds.defaultDataFile) == before)
    }

    @Test func duplicatesCompareLikeTheFileSystem() throws {
        func archive(_ names: [String]) throws -> ZipReader {
            let folder = TempFolder("aa-dupnames")
            let u = folder.file("d.zip")
            let w = try ZipWriter(url: u)
            for n in names {
                if n.hasSuffix("/") { try w.addDirectory(named: n) } else { try w.addData(Data(n.utf8), named: n, modified: nil) }
            }
            try w.finish()
            return try ZipReader(data: try Data(contentsOf: u))
        }
        for pair in [["files/a.pdf", "files/A.PDF"], ["files/a.pdf", #"files\a.pdf"#], ["files/a.pdf", "files//a.pdf"],
                     ["data.json", "./data.json"], ["DATA.JSON", "data.json"]] {
            let r = try archive(pair)
            let folder = TempFolder("aa-dupx")
            #expect(throws: ZipError.self) { try r.extractAll(to: folder.url) }
            #expect(try FileManager.default.contentsOfDirectory(atPath: folder.url.path).isEmpty)
        }
        // Repeated directory entries and Finder metadata are not duplicates.
        let ok = try archive(["files/", "files/", "files/a.pdf", "__MACOSX/._a", "__MACOSX/._a"])
        let folder = TempFolder("aa-dupok")
        try ok.extractAll(to: folder.url)
        #expect(folder.exists("files/a.pdf"))
    }

    // MARK: NFC entry names (V2-COMPAT blocker)

    @Test func writerEmitsNFCNames() throws {
        let folder = TempFolder("aa-nfc")
        let u = folder.file("n.zip")
        let w = try ZipWriter(url: u)
        let nfd = "files/abc_Cafe\u{0301}.pdf"
        try w.addData(Data("x".utf8), named: nfd, modified: nil)
        try w.addDirectory(named: "Pen\u{0303}a/")
        try w.finish()
        let names = try ZipReader(url: u).entries.map { Array($0.name.utf8) }
        #expect(names == [Array("files/abc_Caf\u{E9}.pdf".utf8), Array("Pe\u{F1}a/".utf8)])
    }

    // The verifier's journey (CompatNFCJourneyTests): an accented attachment imported on the Mac is exported under the
    // exact bytes data.json stores, so Windows finds it and its orphan sweep keeps it.
    @MainActor @Test(arguments: ["Caf\u{E9} menu.pdf", "Pe\u{F1}a crew list.xlsx", "\u{D55C}\u{AD6D}\u{C5B4} manual.pdf",
                                 "\u{C5}lesund.txt"])
    func importedAccentedAttachmentExportsByteIdentical(_ leaf: String) throws {
        let made = StoreFactory.make()
        let ds = made.dataStore
        let src = TempFolder("aa-nfc-src")
        let f = src.url.appending(path: leaf)
        try Data("x".utf8).write(to: f)
        let s = try AttachmentStore.importFile(ds, from: f)
        #expect(s == s.precomposedStringWithCanonicalMapping)                  // data.json stores NFC
        let d = AppData()
        let e = Equipment(name: "e")
        e.container.files.append(FileItem(name: "f", path: s))
        d.equipment.append(e)
        try ds.persistWriteReplacing(try ds.serializeForSave(d), to: ds.defaultDataFile)
        let out = src.file("out.zip")
        try BundleService.exportFolderToZipSync(ds, to: out, includeAttachments: true)
        let names = Set(try ZipReader(url: out).entries.map { Array($0.name.utf8) })
        #expect(names.contains(Array(s.utf8)))
    }

    // Windows → Mac → Windows: the NFC entry of a Windows bundle lands on disk (decomposed by the file system) and is
    // exported again under the original NFC bytes.
    @MainActor @Test(arguments: ["zip64", "backslash"])
    func windowsNFCEntrySurvivesTheRoundTrip(_ name: String) throws {
        let made = StoreFactory.make()
        let ds = made.dataStore
        _ = try BundleService.importBundleSmart(ds, from: Fixtures.url("zip/hostile/\(name).zip"))
        let outFolder = TempFolder("aa-nfc-out")
        let out = outFolder.file("re-export.zip")
        try BundleService.exportFolderToZipSync(ds, to: out, includeAttachments: true)
        let names = Set(try ZipReader(url: out).entries.map { Array($0.name.utf8) })
        #expect(names.contains(Array("files/abc_Caf\u{E9}.pdf".utf8)))
        #expect(!names.contains(Array("files/abc_Cafe\u{0301}.pdf".utf8)))
    }

    // MARK: Builders

    /// One stored/deflate entry whose central record carries a Zip64 extra with the given usize/csize/offset; the
    /// local header (5 bytes "hello") sits at 0.
    static func zip64Entry(usize: UInt64, csize: UInt64, offset: UInt64, method: UInt16) -> Data {
        let name = Array("data.json".utf8)
        var body = ZipBytes()
        body.u32(ZipFormat.localSig); body.u16(45); body.u16(0); body.u16(method); body.u16(0); body.u16(0x5B21)
        body.u32(CRC32.checksum(Array("hello".utf8))); body.u32(5); body.u32(5)
        body.u16(UInt16(name.count)); body.u16(0); body.raw(name); body.raw(Array("hello".utf8))
        var extra = ZipBytes()
        extra.u16(ZipFormat.zip64ExtraID); extra.u16(24); extra.u64(usize); extra.u64(csize); extra.u64(offset)
        var cen = ZipBytes()
        cen.u32(ZipFormat.centralSig); cen.u16(45); cen.u16(45); cen.u16(0); cen.u16(method); cen.u16(0); cen.u16(0x5B21)
        cen.u32(CRC32.checksum(Array("hello".utf8))); cen.u32(0xFFFF_FFFF); cen.u32(0xFFFF_FFFF)
        cen.u16(UInt16(name.count)); cen.u16(UInt16(extra.bytes.count)); cen.u16(0); cen.u16(0); cen.u16(0); cen.u32(0)
        cen.u32(0xFFFF_FFFF); cen.raw(name); cen.raw(extra.bytes)
        var out = ZipBytes()
        out.raw(body.bytes); out.raw(cen.bytes)
        out.u32(ZipFormat.eocdSig); out.u16(0); out.u16(0); out.u16(1); out.u16(1)
        out.u32(UInt32(cen.bytes.count)); out.u32(UInt32(body.bytes.count)); out.u16(0)
        return Data(out.bytes)
    }
}
