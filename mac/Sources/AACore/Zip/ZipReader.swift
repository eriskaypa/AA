// Spec: 01 §4.5, §6.7 (Deflate + Stored, Zip64, data descriptors, UTF-8 / CP437 names, reject absolute and `..`
//       entries, never create symlinks, streaming), 01 §7.7 (`../evil.txt` rejected); ARCHITECTURE.md §6.4.
import Foundation

/// Random-access byte source of an archive (a file or memory).
protocol ZipByteSource: AnyObject {
    var size: UInt64 { get }
    func read(at offset: UInt64, count: Int) throws(ZipError) -> [UInt8]
}

final class ZipMemorySource: ZipByteSource {
    let data: [UInt8]
    init(_ d: Data) { data = [UInt8](d) }
    var size: UInt64 { UInt64(data.count) }
    func read(at offset: UInt64, count: Int) throws(ZipError) -> [UInt8] {
        guard offset <= UInt64(data.count), count >= 0, Int(offset) + count <= data.count else {
            throw .corrupt("read past the end of the archive")
        }
        return Array(data[Int(offset)..<(Int(offset) + count)])
    }
}

final class ZipFileSource: ZipByteSource {
    let handle: FileHandle
    let size: UInt64
    init(url: URL) throws(ZipError) {
        do {
            handle = try FileHandle(forReadingFrom: url)
            size = try handle.seekToEnd()
        } catch {
            throw .io("Could not open \(url.path): \(error.localizedDescription)")
        }
    }
    deinit { try? handle.close() }
    func read(at offset: UInt64, count: Int) throws(ZipError) -> [UInt8] {
        guard offset + UInt64(max(count, 0)) <= size else { throw .corrupt("read past the end of the archive") }
        do {
            try handle.seek(toOffset: offset)
            let d = try handle.read(upToCount: count) ?? Data()
            guard d.count == count else { throw ZipError.corrupt("short read") }
            return [UInt8](d)
        } catch let e as ZipError {
            throw e
        } catch {
            throw .io(error.localizedDescription)
        }
    }
}

public final class ZipReader {
    private let source: ZipByteSource
    public let entries: [ZipEntryInfo]
    private let flagsByOffset: [UInt64: UInt16]

    public convenience init(url: URL) throws(ZipError) {
        try self.init(source: try ZipFileSource(url: url))
    }

    public convenience init(data: Data) throws(ZipError) {
        try self.init(source: ZipMemorySource(data))
    }

    init(source: ZipByteSource) throws(ZipError) {
        self.source = source
        let (list, flags) = try ZipReader.readCentralDirectory(source)
        entries = list
        flagsByOffset = flags
    }

    /// Case-sensitive (ordinal) lookup; the first entry with that exact name.
    public func entry(named name: String) -> ZipEntryInfo? {
        entries.first { Ordinal.equals($0.name, name) }
    }

    // MARK: Central directory

    static func readCentralDirectory(_ src: ZipByteSource) throws(ZipError) -> ([ZipEntryInfo], [UInt64: UInt16]) {
        let size = src.size
        guard size >= 22 else { throw .notAZip }
        let tailLen = Int(min(size, 65_557))
        let tailStart = size - UInt64(tailLen)
        let tail = try src.read(at: tailStart, count: tailLen)
        var eocd = -1
        var k = tail.count - 22
        while k >= 0 {
            if tail[k] == 0x50, tail[k + 1] == 0x4B, tail[k + 2] == 0x05, tail[k + 3] == 0x06 {
                let commentLen = Int(tail[k + 20]) | Int(tail[k + 21]) << 8
                if k + 22 + commentLen <= tail.count { eocd = k; break }
            }
            k -= 1
        }
        guard eocd >= 0 else { throw .notAZip }
        var c = ZipReadCursor(tail, eocd + 4)
        _ = try c.u16(); _ = try c.u16()
        _ = try c.u16()
        var total = UInt64(try c.u16())
        var cdSize = UInt64(try c.u32())
        var cdOffset = UInt64(try c.u32())
        if total == 0xFFFF || cdSize == 0xFFFF_FFFF || cdOffset == 0xFFFF_FFFF {
            let locatorPos = Int(tailStart) + eocd - 20
            if locatorPos >= 0 {
                var lc = ZipReadCursor(try src.read(at: UInt64(locatorPos), count: 20))
                if try lc.u32() == ZipFormat.zip64LocatorSig {
                    _ = try lc.u32()
                    let z64 = try lc.u64()
                    var zc = ZipReadCursor(try src.read(at: z64, count: 56))
                    guard try zc.u32() == ZipFormat.zip64EocdSig else { throw .corrupt("bad Zip64 end record") }
                    _ = try zc.u64(); _ = try zc.u16(); _ = try zc.u16(); _ = try zc.u32(); _ = try zc.u32()
                    _ = try zc.u64()
                    total = try zc.u64()
                    cdSize = try zc.u64()
                    cdOffset = try zc.u64()
                }
            }
        }
        guard cdOffset + cdSize <= size, cdSize <= UInt64(Int.max) else { throw .corrupt("bad central directory") }
        let cd = try src.read(at: cdOffset, count: Int(cdSize))
        var cur = ZipReadCursor(cd)
        var list: [ZipEntryInfo] = []
        var flagsByOffset: [UInt64: UInt16] = [:]
        var n: UInt64 = 0
        while n < total && cur.remaining >= 46 {
            guard try cur.u32() == ZipFormat.centralSig else { throw .corrupt("bad central directory entry") }
            _ = try cur.u16(); _ = try cur.u16()
            let flags = try cur.u16()
            let method = try cur.u16()
            let time = try cur.u16(), date = try cur.u16()
            let crc = try cur.u32()
            var csize = UInt64(try cur.u32()), usize = UInt64(try cur.u32())
            let nameLen = Int(try cur.u16()), extraLen = Int(try cur.u16()), commentLen = Int(try cur.u16())
            _ = try cur.u16(); _ = try cur.u16(); _ = try cur.u32()
            var offset = UInt64(try cur.u32())
            let nameBytes = try cur.take(nameLen)
            let extra = try cur.take(extraLen)
            _ = try cur.take(commentLen)
            let utf8 = (flags & ZipFormat.flagUTF8) != 0
            var name = ZipFormat.decodeName(nameBytes, utf8: utf8)
            var ec = ZipReadCursor(extra)
            while ec.remaining >= 4 {
                let id = try ec.u16(), len = Int(try ec.u16())
                guard ec.remaining >= len else { break }
                var field = ZipReadCursor(try ec.take(len))
                if id == ZipFormat.zip64ExtraID {
                    if usize == 0xFFFF_FFFF, field.remaining >= 8 { usize = try field.u64() }
                    if csize == 0xFFFF_FFFF, field.remaining >= 8 { csize = try field.u64() }
                    if offset == 0xFFFF_FFFF, field.remaining >= 8 { offset = try field.u64() }
                } else if id == ZipFormat.unicodePathExtraID, !utf8, field.remaining >= 5 {
                    _ = try field.take(1)
                    let nameCRC = try field.u32()
                    if nameCRC == CRC32.checksum(nameBytes) {
                        name = String(decoding: try field.take(field.remaining), as: UTF8.self)
                    }
                }
            }
            let isDir = name.hasSuffix("/") || name.hasSuffix("\\")
            list.append(ZipEntryInfo(name: name, isDirectory: isDir, method: method, compressedSize: csize,
                                     uncompressedSize: usize, crc32: crc,
                                     modified: ZipFormat.date(dosTime: time, dosDate: date), isUTF8: utf8,
                                     localHeaderOffset: offset))
            flagsByOffset[offset] = flags
            n += 1
        }
        return (list, flagsByOffset)
    }

    // MARK: Reading entries

    private func dataStart(of entry: ZipEntryInfo) throws(ZipError) -> UInt64 {
        var h = ZipReadCursor(try source.read(at: entry.localHeaderOffset, count: 30))
        guard try h.u32() == ZipFormat.localSig else { throw .corrupt("bad local header for \(entry.name)") }
        h.i = 26
        let nameLen = UInt64(try h.u16()), extraLen = UInt64(try h.u16())
        return entry.localHeaderOffset + 30 + nameLen + extraLen
    }

    private func checkSupported(_ entry: ZipEntryInfo) throws(ZipError) {
        if let f = flagsByOffset[entry.localHeaderOffset], (f & 1) != 0 { throw .unsupported("encrypted entry \(entry.name)") }
        guard entry.method == 0 || entry.method == 8 else { throw .unsupported("compression method \(entry.method)") }
    }

    /// The whole entry in memory (for small entries such as data.json / source.json). CRC-checked.
    public func data(for entry: ZipEntryInfo) throws(ZipError) -> Data {
        if entry.isDirectory { return Data() }
        try checkSupported(entry)
        guard entry.compressedSize <= UInt64(Int.max), entry.uncompressedSize <= UInt64(Int.max) else {
            throw .unsupported("entry too large for memory")
        }
        let start = try dataStart(of: entry)
        let raw = try source.read(at: start, count: Int(entry.compressedSize))
        let out: [UInt8]
        if entry.method == 0 {
            out = raw
        } else {
            do { out = try RawDeflate.inflate(raw, expectedLength: Int(entry.uncompressedSize)) } catch {
                throw .corrupt("\(entry.name) could not be inflated")
            }
        }
        guard CRC32.checksum(out) == entry.crc32 else { throw .crcMismatch(entry.name) }
        return Data(out)
    }

    /// Streams the entry to `url` (created/overwritten), CRC- and size-checked; a damaged entry leaves no file.
    public func extract(_ entry: ZipEntryInfo, to url: URL) throws(ZipError) {
        try checkSupported(entry)
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        } catch {
            throw .io(error.localizedDescription)
        }
        guard fm.createFile(atPath: url.path, contents: nil),
              let out = try? FileHandle(forWritingTo: url) else { throw .io("Could not create \(url.path)") }
        var ok = false
        defer {
            try? out.close()
            if !ok { try? fm.removeItem(at: url) }
        }
        var crc: UInt32 = 0
        var produced: UInt64 = 0
        var writeFailure: String?
        let sink: (UnsafeBufferPointer<UInt8>) -> Void = { chunk in
            guard writeFailure == nil else { return }
            crc = CRC32.checksum(UnsafeRawBufferPointer(chunk), seed: crc)
            produced += UInt64(chunk.count)
            do { try out.write(contentsOf: Data(buffer: chunk)) } catch { writeFailure = error.localizedDescription }
        }
        var pos = try dataStart(of: entry)
        var left = entry.compressedSize
        let chunkSize = 1 << 20
        let codec: RawDeflateCodec? = entry.method == 8 ? (try? RawDeflateCodec(encode: false)) : nil
        if entry.method == 8 && codec == nil { throw .io("Could not start decompression") }
        while left > 0 {
            let n = Int(min(UInt64(chunkSize), left))
            let chunk = try source.read(at: pos, count: n)
            pos += UInt64(n); left -= UInt64(n)
            if let codec {
                do {
                    try chunk.withUnsafeBytes { raw in _ = try codec.process(raw, finalize: left == 0) { sink($0) } }
                } catch {
                    throw .corrupt("\(entry.name) could not be inflated")
                }
            } else {
                chunk.withUnsafeBufferPointer { sink($0) }
            }
            if let writeFailure { throw .io(writeFailure) }
        }
        if let writeFailure { throw .io(writeFailure) }
        guard produced == entry.uncompressedSize, crc == entry.crc32 else { throw .crcMismatch(entry.name) }
        ok = true
    }

    /// Extracts every entry under `folder`, skipping Finder metadata by default. Entries that are absolute,
    /// drive-qualified or climb out with `..` are rejected (nothing is written outside `folder`); symlinks are
    /// never created.
    public func extractAll(to folder: URL, skip: (String) -> Bool = ZipReader.isFinderMetadata) throws(ZipError) {
        let root = folder.standardizedFileURL
        let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
        var plan: [(ZipEntryInfo, URL)] = []
        for e in entries {
            if skip(e.name) { continue }
            guard let rel = ZipFormat.safeRelativePath(e.name) else { throw .unsafePath(e.name) }
            let dest = root.appending(path: rel).standardizedFileURL
            guard (dest.path + (e.isDirectory ? "/" : "")).hasPrefix(rootPath) else { throw .unsafePath(e.name) }
            plan.append((e, dest))
        }
        for (e, dest) in plan {
            if e.isDirectory {
                do { try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true) } catch {
                    throw .io(error.localizedDescription)
                }
            } else {
                try extract(e, to: dest)
            }
        }
    }

    /// `.DS_Store`, `._*`, `__MACOSX/`, `Icon\r` — never bundled, extracted, counted or swept.
    public static func isFinderMetadata(_ name: String) -> Bool {
        let parts = name.replacingOccurrences(of: "\\", with: "/").split(separator: "/", omittingEmptySubsequences: true)
        if parts.first == "__MACOSX" { return true }
        guard let last = parts.last else { return false }
        return last == ".DS_Store" || last.hasPrefix("._") || last == "Icon\r"
    }
}
