// TV: 01 §6.7 (Deflate + Stored, Zip64, data descriptors, UTF-8 flag / CP437 names, unsafe entries, Finder metadata),
//     01 §4.5 (empty `files/` directory entry), 01 §7.7 (`../evil.txt` rejected), ARCHITECTURE.md §6.4, §10.3.
import Foundation
import Testing
@testable import AACore

/// Hand-built archive pieces (stored entries) for reader edge cases the writer never produces.
private struct HandZip {
    var body = ZipBytes()
    var central = ZipBytes()
    var count: UInt16 = 0

    mutating func addStored(nameBytes: [UInt8], data: [UInt8], flags: UInt16 = 0, crc: UInt32? = nil,
                            descriptor: Bool = false, method: UInt16 = 0) {
        let offset = UInt32(body.bytes.count)
        let c = crc ?? CRC32.checksum(data)
        let f = flags | (descriptor ? ZipFormat.flagDataDescriptor : 0)
        body.u32(ZipFormat.localSig); body.u16(20); body.u16(f); body.u16(method); body.u16(0); body.u16(0x5B21)
        body.u32(descriptor ? 0 : c)
        body.u32(descriptor ? 0 : UInt32(data.count)); body.u32(descriptor ? 0 : UInt32(data.count))
        body.u16(UInt16(nameBytes.count)); body.u16(0); body.raw(nameBytes); body.raw(data)
        if descriptor { body.u32(ZipFormat.dataDescriptorSig); body.u32(c); body.u32(UInt32(data.count)); body.u32(UInt32(data.count)) }
        central.u32(ZipFormat.centralSig); central.u16(20); central.u16(20); central.u16(f); central.u16(method)
        central.u16(0); central.u16(0x5B21); central.u32(c); central.u32(UInt32(data.count)); central.u32(UInt32(data.count))
        central.u16(UInt16(nameBytes.count)); central.u16(0); central.u16(0); central.u16(0); central.u16(0); central.u32(0)
        central.u32(offset); central.raw(nameBytes)
        count += 1
    }

    func finish(comment: [UInt8] = []) -> Data {
        var out = ZipBytes()
        out.raw(body.bytes); out.raw(central.bytes)
        out.u32(ZipFormat.eocdSig); out.u16(0); out.u16(0); out.u16(count); out.u16(count)
        out.u32(UInt32(central.bytes.count)); out.u32(UInt32(body.bytes.count)); out.u16(UInt16(comment.count))
        out.raw(comment)
        return Data(out.bytes)
    }
}

@Suite struct ZipTests {
    func le32(_ b: [UInt8], _ i: Int) -> UInt32 {
        UInt32(b[i]) | UInt32(b[i + 1]) << 8 | UInt32(b[i + 2]) << 16 | UInt32(b[i + 3]) << 24
    }
    func le16(_ b: [UInt8], _ i: Int) -> UInt16 { UInt16(b[i]) | UInt16(b[i + 1]) << 8 }

    // Bundle-shaped round trip incl. the empty `files/` directory entry (01 §4.5)
    @Test func roundTripWithEmptyFilesDirectory() throws {
        let folder = TempFolder()
        let url = folder.file("bundle.aaz")
        let source = Data(#"{"Identity":"Vessel-Alpha"}"#.utf8)
        let big = Data((0..<300_000).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ $0 >> 7) })
        try folder.write("big.bin", big)
        let modified = Date(timeIntervalSince1970: 1_790_000_000)
        let w = try ZipWriter(url: url)
        try w.addData(Data(Goldens.freshDB.utf8), named: "data.json", modified: modified)
        try w.addData(source, named: "source.json", modified: modified, compress: false)
        try w.addDirectory(named: "files")
        try w.addFile(named: "files/sub/big.bin", from: folder.file("big.bin"), modified: modified)
        try w.addData(Data(), named: "empty.txt", modified: nil)
        try w.finish()

        let r = try ZipReader(url: url)
        #expect(r.entries.map(\.name) == ["data.json", "source.json", "files/", "files/sub/big.bin", "empty.txt"])
        let dir = try #require(r.entry(named: "files/"))
        #expect(dir.isDirectory && dir.method == 0 && dir.compressedSize == 0 && dir.uncompressedSize == 0 && dir.crc32 == 0)
        #expect(try r.data(for: dir).isEmpty)
        #expect(try r.data(for: #require(r.entry(named: "data.json"))) == Data(Goldens.freshDB.utf8))
        let src = try #require(r.entry(named: "source.json"))
        #expect(src.method == 0 && src.compressedSize == UInt64(source.count))
        #expect(try r.data(for: src) == source)
        let bigEntry = try #require(r.entry(named: "files/sub/big.bin"))
        #expect(bigEntry.method == 8 && bigEntry.uncompressedSize == 300_000 && bigEntry.compressedSize < 300_000)
        #expect(bigEntry.crc32 == CRC32.checksum(big))
        #expect(try r.data(for: bigEntry) == big)
        #expect(try r.data(for: #require(r.entry(named: "empty.txt"))).isEmpty)
        #expect(r.entry(named: "DATA.JSON") == nil)                                  // case-sensitive
        // DOS time keeps 2-second resolution in local time
        let m = try #require(r.entry(named: "data.json")?.modified)
        #expect(abs(m.timeIntervalSince(modified)) <= 2)
        // Streaming extraction
        try r.extract(bigEntry, to: folder.file("out/big.bin"))
        #expect(try folder.read("out/big.bin") == big)
        try r.extractAll(to: folder.file("all"))
        #expect(try folder.read("all/files/sub/big.bin") == big)
        var isDir: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: folder.file("all/files").path, isDirectory: &isDir) && isDir.boolValue)
        // In-memory reader sees the same archive.
        let mem = try ZipReader(data: try Data(contentsOf: url))
        #expect(mem.entries == r.entries)
    }

    // Zip64 headers (forced): version 45 + extra 0x0001 locally and centrally, Zip64 EOCD + locator; reader round trip
    @Test func zip64Headers() throws {
        let folder = TempFolder()
        let url = folder.file("z64.zip")
        let w = try ZipWriter(url: url)
        w.forceZip64 = true
        try w.addData(Data("hello zip64".utf8), named: "a.txt", modified: nil)
        try w.addDirectory(named: "files/")
        try w.finish()
        let b = [UInt8](try Data(contentsOf: url))
        #expect(le32(b, 0) == ZipFormat.localSig && le16(b, 4) == 45)
        #expect(le32(b, 18) == 0xFFFF_FFFF && le32(b, 22) == 0xFFFF_FFFF)            // sizes deferred to the extra
        let nameLen = Int(le16(b, 26))
        #expect(le16(b, 28) == 20 && le16(b, 30 + nameLen) == 0x0001 && le16(b, 32 + nameLen) == 16)
        let data = Data(b)
        #expect(data.range(of: Data([0x50, 0x4B, 0x06, 0x06])) != nil)              // Zip64 end of central directory
        #expect(data.range(of: Data([0x50, 0x4B, 0x06, 0x07])) != nil)              // Zip64 locator
        let eocd = try #require(data.range(of: Data([0x50, 0x4B, 0x05, 0x06]), options: .backwards)).lowerBound
        #expect(le16(b, eocd + 10) == 0xFFFF && le32(b, eocd + 12) == 0xFFFF_FFFF && le32(b, eocd + 16) == 0xFFFF_FFFF)
        let r = try ZipReader(url: url)
        #expect(r.entries.map(\.name) == ["a.txt", "files/"])
        let a = try #require(r.entry(named: "a.txt"))
        #expect(a.uncompressedSize == 11 && a.localHeaderOffset == 0)
        #expect(try r.data(for: a) == Data("hello zip64".utf8))
        #expect(r.entries[1].isDirectory)
    }

    // UTF-8 flag only for non-ASCII names (01 §6.7)
    @Test func utf8Flag() throws {
        let folder = TempFolder()
        let url = folder.file("names.zip")
        let w = try ZipWriter(url: url)
        try w.addData(Data("1".utf8), named: "files/abc_Manual.pdf", modified: nil)
        try w.addData(Data("2".utf8), named: "files/abc_Pump \u{2192} \u{2693} caf\u{E9}.pdf", modified: nil)
        try w.finish()
        let r = try ZipReader(url: url)
        #expect(r.entries.map(\.isUTF8) == [false, true])
        #expect(r.entries[1].name == "files/abc_Pump \u{2192} \u{2693} caf\u{E9}.pdf")
        let b = [UInt8](try Data(contentsOf: url))
        #expect(le16(b, 6) & ZipFormat.flagUTF8 == 0)
    }

    // CP437 names without the UTF-8 flag; data descriptors; archive comments
    @Test func readerEdgeCases() throws {
        var z = HandZip()
        z.addStored(nameBytes: [0x63, 0x61, 0x66, 0x82, 0x2E, 0x74, 0x78, 0x74], data: Array("x".utf8))   // "café.txt" in CP437
        z.addStored(nameBytes: Array("dd.txt".utf8), data: Array("descriptor".utf8), descriptor: true)
        z.addStored(nameBytes: Array("u8.txt".utf8), data: Array("y".utf8), flags: ZipFormat.flagUTF8)
        let r = try ZipReader(data: z.finish(comment: Array("a comment PK".utf8)))
        #expect(r.entries.map(\.name) == ["caf\u{E9}.txt", "dd.txt", "u8.txt"])
        #expect(r.entries.map(\.isUTF8) == [false, false, true])
        #expect(try r.data(for: r.entries[1]) == Data("descriptor".utf8))
        #expect(ZipFormat.decodeName([0x80, 0xE1, 0xFF], utf8: false) == "\u{C7}\u{DF}\u{A0}")
    }

    @Test func damagedArchives() throws {
        #expect(throws: ZipError.notAZip) { try ZipReader(data: Data("not a zip at all, definitely not".utf8)) }
        #expect(throws: ZipError.notAZip) { try ZipReader(data: Data()) }
        var z = HandZip()
        z.addStored(nameBytes: Array("a.txt".utf8), data: Array("hello".utf8), crc: 0xDEAD_BEEF)
        let bad = try ZipReader(data: z.finish())
        #expect(throws: ZipError.crcMismatch("a.txt")) { try bad.data(for: bad.entries[0]) }
        let folder = TempFolder()
        #expect(throws: ZipError.crcMismatch("a.txt")) { try bad.extract(bad.entries[0], to: folder.file("a.txt")) }
        #expect(!folder.exists("a.txt"))                                            // a damaged entry leaves no file
        var enc = HandZip()
        enc.addStored(nameBytes: Array("e.txt".utf8), data: Array("x".utf8), flags: 1)
        let e = try ZipReader(data: enc.finish())
        #expect(throws: ZipError.self) { try e.data(for: e.entries[0]) }
        var m = HandZip()
        m.addStored(nameBytes: Array("m.txt".utf8), data: Array("x".utf8), method: 14)
        let lz = try ZipReader(data: m.finish())
        #expect(throws: ZipError.unsupported("compression method 14")) { try lz.data(for: lz.entries[0]) }
    }

    // TV: 01 §7.7 — `../evil.txt` (and absolute / drive-qualified names) are rejected; nothing is written
    @Test(arguments: ["../evil.txt", "files/../../evil.txt", "/etc/evil.txt", #"C:\evil.txt"#, #"..\evil.txt"#])
    func unsafeEntries(_ name: String) throws {
        var z = HandZip()
        z.addStored(nameBytes: Array("ok.txt".utf8), data: Array("ok".utf8))
        z.addStored(nameBytes: Array(name.utf8), data: Array("evil".utf8))
        let r = try ZipReader(data: z.finish())
        let folder = TempFolder()
        let dest = folder.file("x")
        #expect(throws: ZipError.unsafePath(name)) { try r.extractAll(to: dest) }
        #expect(!FileManager.default.fileExists(atPath: dest.appending(path: "ok.txt").path))
        #expect(!folder.exists("evil.txt"))
    }

    @Test func safeRelativePaths() {
        #expect(ZipFormat.safeRelativePath("files/a.pdf") == "files/a.pdf")
        #expect(ZipFormat.safeRelativePath(#"files\a.pdf"#) == "files/a.pdf")
        #expect(ZipFormat.safeRelativePath("./files//a.pdf") == "files/a.pdf")
        #expect(ZipFormat.safeRelativePath("files/") == "files/")
        #expect(ZipFormat.safeRelativePath("") == nil)
        #expect(ZipFormat.safeRelativePath("a/../b") == nil)
    }

    // Finder metadata is never extracted
    @Test func finderMetadata() throws {
        for n in [".DS_Store", "files/.DS_Store", "files/._x.pdf", "__MACOSX/files/x.pdf", "Icon\r", #"files\._y"#] {
            #expect(ZipReader.isFinderMetadata(n), "\(n)")
        }
        for n in ["files/x.pdf", "files/x.DS_Store", "_x", "files/Icon", "MACOSX/x"] {
            #expect(!ZipReader.isFinderMetadata(n), "\(n)")
        }
        var z = HandZip()
        z.addStored(nameBytes: Array("files/a.txt".utf8), data: Array("a".utf8))
        z.addStored(nameBytes: Array("files/.DS_Store".utf8), data: Array("junk".utf8))
        z.addStored(nameBytes: Array("__MACOSX/files/._a.txt".utf8), data: Array("junk".utf8))
        let folder = TempFolder()
        try ZipReader(data: z.finish()).extractAll(to: folder.url)
        #expect(folder.exists("files/a.txt") && !folder.exists("files/.DS_Store") && !folder.exists("__MACOSX"))
    }

    // Interop: archives from the system `ditto` (Deflate + data descriptors) read back; ours pass `unzip -t`.
    @Test(.enabled(if: FileManager.default.isExecutableFile(atPath: "/usr/bin/ditto")
                   && FileManager.default.isExecutableFile(atPath: "/usr/bin/unzip")))
    func systemInterop() throws {
        let folder = TempFolder()
        let payload = Data((0..<50_000).map { UInt8(truncatingIfNeeded: $0 % 251) })
        try folder.write("src/files/a.bin", payload)
        try folder.write("src/data.json", Goldens.freshDB)
        try run("/usr/bin/ditto", ["-c", "-k", "--norsrc", folder.file("src").path, folder.file("ditto.zip").path])
        let r = try ZipReader(url: folder.file("ditto.zip"))
        #expect(try r.data(for: #require(r.entry(named: "files/a.bin"))) == payload)
        #expect(try r.data(for: #require(r.entry(named: "data.json"))) == Data(Goldens.freshDB.utf8))
        let w = try ZipWriter(url: folder.file("ours.zip"))
        try w.addData(payload, named: "files/a.bin", modified: nil)
        try w.addDirectory(named: "files/empty")
        try w.addData(Data("x".utf8), named: "caf\u{E9}.txt", modified: nil)
        try w.finish()
        try run("/usr/bin/unzip", ["-tqq", folder.file("ours.zip").path])
        let z64 = try ZipWriter(url: folder.file("ours64.zip"))
        z64.forceZip64 = true
        try z64.addData(payload, named: "files/a.bin", modified: nil)
        try z64.finish()
        try run("/usr/bin/unzip", ["-tqq", folder.file("ours64.zip").path])
    }

    private func run(_ tool: String, _ args: [String]) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try p.run()
        p.waitUntilExit()
        #expect(p.terminationStatus == 0, "\(tool) \(args)")
    }
}
