// Spec: 01 §4.5 (bundle entries, `files/` directory entry only when empty), §6.7 (Deflate, UTF-8 flag for non-ASCII
//       names, Zip64 when needed, streaming), 09 §3.10 / 11 §4.5.7 (XLSX packages); ARCHITECTURE.md §6.4.
import Foundation

public final class ZipWriter {
    private struct Record {
        var nameBytes: [UInt8]
        var flags: UInt16
        var method: UInt16
        var time: UInt16, date: UInt16
        var crc: UInt32
        var csize: UInt64, usize: UInt64
        var offset: UInt64
        var zip64Local: Bool
        var isDirectory: Bool
    }

    private let handle: FileHandle
    private let url: URL
    private var records: [Record] = []
    private var position: UInt64 = 0
    private var finished = false
    /// Test hook: write Zip64 extra fields and end records even for small archives.
    var forceZip64 = false
    /// Entries at or above this size get Zip64 local headers (streaming cannot know the compressed size up front).
    static let zip64Threshold: UInt64 = 0xFFFF_0000

    public init(url: URL) throws(ZipError) {
        self.url = url
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fm.fileExists(atPath: url.path) { try fm.removeItem(at: url) }
        } catch {
            throw .io(error.localizedDescription)
        }
        guard fm.createFile(atPath: url.path, contents: nil), let h = try? FileHandle(forWritingTo: url) else {
            throw .io("Could not create \(url.path)")
        }
        handle = h
    }

    deinit { if !finished { try? handle.close() } }

    // MARK: Public API

    /// Streams a file into a Deflate entry.
    public func addFile(named name: String, from source: URL, modified: Date?) throws(ZipError) {
        let input: FileHandle
        let size: UInt64
        do {
            input = try FileHandle(forReadingFrom: source)
            size = try input.seekToEnd()
            try input.seek(toOffset: 0)
        } catch {
            throw .io("Could not read \(source.path): \(error.localizedDescription)")
        }
        defer { try? input.close() }
        try writeEntry(name: name, modified: modified ?? Date(), method: 8, knownSize: size) { (feed: ([UInt8]) throws(ZipError) -> Void) throws(ZipError) in
            while true {
                let chunk: Data
                do { chunk = try input.read(upToCount: 1 << 20) ?? Data() } catch {
                    throw ZipError.io("Could not read \(source.path): \(error.localizedDescription)")
                }
                if chunk.isEmpty { break }
                try feed([UInt8](chunk))
            }
        }
    }

    public func addData(_ data: Data, named name: String, modified: Date?, compress: Bool = true) throws(ZipError) {
        try writeEntry(name: name, modified: modified ?? Date(), method: compress ? 8 : 0, knownSize: UInt64(data.count)) { (feed: ([UInt8]) throws(ZipError) -> Void) throws(ZipError) in
            if !data.isEmpty { try feed([UInt8](data)) }
        }
    }

    /// A bare directory entry, e.g. `"files/"` (a trailing `/` is added when missing).
    public func addDirectory(named name: String) throws(ZipError) {
        let n = name.hasSuffix("/") ? name : name + "/"
        let (nameBytes, flags) = encodedName(n)
        let (t, d) = ZipFormat.dosDateTime(Date())
        let zip64 = forceZip64
        let offset = position
        try writeLocalHeader(nameBytes: nameBytes, flags: flags, method: 0, time: t, date: d, zip64: zip64)
        records.append(Record(nameBytes: nameBytes, flags: flags, method: 0, time: t, date: d, crc: 0, csize: 0, usize: 0,
                              offset: offset, zip64Local: zip64, isDirectory: true))
    }

    /// Writes the central directory (and Zip64 end records when needed) and closes the file.
    public func finish() throws(ZipError) {
        guard !finished else { return }
        let cdStart = position
        for r in records {
            var b = ZipBytes()
            let needOffset64 = r.offset >= 0xFFFF_FFFF || forceZip64
            let sizes64 = r.zip64Local
            b.u32(ZipFormat.centralSig)
            let version: UInt16 = (sizes64 || needOffset64) ? 45 : 20
            b.u16(version); b.u16(version)
            b.u16(r.flags); b.u16(r.method); b.u16(r.time); b.u16(r.date); b.u32(r.crc)
            b.u32(sizes64 ? 0xFFFF_FFFF : UInt32(r.csize))
            b.u32(sizes64 ? 0xFFFF_FFFF : UInt32(r.usize))
            var extra = ZipBytes()
            if sizes64 || needOffset64 {
                var f = ZipBytes()
                if sizes64 { f.u64(r.usize); f.u64(r.csize) }
                if needOffset64 { f.u64(r.offset) }
                extra.u16(ZipFormat.zip64ExtraID); extra.u16(UInt16(f.bytes.count)); extra.raw(f.bytes)
            }
            b.u16(UInt16(r.nameBytes.count)); b.u16(UInt16(extra.bytes.count)); b.u16(0)
            b.u16(0); b.u16(0)
            b.u32(r.isDirectory ? 0x10 : 0)
            b.u32(needOffset64 ? 0xFFFF_FFFF : UInt32(r.offset))
            b.raw(r.nameBytes); b.raw(extra.bytes)
            try write(b.bytes)
        }
        let cdSize = position - cdStart
        let needZip64 = forceZip64 || records.count >= 0xFFFF || cdStart >= 0xFFFF_FFFF || cdSize >= 0xFFFF_FFFF
        var e = ZipBytes()
        if needZip64 {
            let z64 = position
            e.u32(ZipFormat.zip64EocdSig); e.u64(44); e.u16(45); e.u16(45); e.u32(0); e.u32(0)
            e.u64(UInt64(records.count)); e.u64(UInt64(records.count)); e.u64(cdSize); e.u64(cdStart)
            e.u32(ZipFormat.zip64LocatorSig); e.u32(0); e.u64(z64); e.u32(1)
        }
        e.u32(ZipFormat.eocdSig); e.u16(0); e.u16(0)
        let count16: UInt16 = needZip64 ? 0xFFFF : UInt16(records.count)
        e.u16(count16); e.u16(count16)
        e.u32(needZip64 ? 0xFFFF_FFFF : UInt32(cdSize))
        e.u32(needZip64 ? 0xFFFF_FFFF : UInt32(cdStart))
        e.u16(0)
        try write(e.bytes)
        do {
            try handle.synchronize()
            try handle.close()
        } catch {
            throw .io(error.localizedDescription)
        }
        finished = true
    }

    // MARK: Internals

    /// Entry names are written in Unicode NFC. Names read back from the Mac file system are decomposed (NFD,
    /// via `fileSystemRepresentation`) while data.json stores the NFC leaf and NTFS compares names byte for byte,
    /// so an NFD entry would not match its data.json path on Windows (01 §6.6, DATA-041/045).
    static func entryName(_ name: String) -> String { name.precomposedStringWithCanonicalMapping }

    private func encodedName(_ name: String) -> ([UInt8], UInt16) {
        let bytes = Array(ZipWriter.entryName(name).utf8)
        return (bytes, bytes.allSatisfy { $0 < 0x80 } ? 0 : ZipFormat.flagUTF8)
    }

    private func write(_ bytes: [UInt8]) throws(ZipError) {
        do { try handle.write(contentsOf: bytes) } catch { throw .io(error.localizedDescription) }
        position += UInt64(bytes.count)
    }

    private func writeLocalHeader(nameBytes: [UInt8], flags: UInt16, method: UInt16, time: UInt16, date: UInt16,
                                  zip64: Bool) throws(ZipError) {
        var b = ZipBytes()
        b.u32(ZipFormat.localSig)
        b.u16(zip64 ? 45 : 20)
        b.u16(flags); b.u16(method); b.u16(time); b.u16(date)
        b.u32(0)                                                    // CRC, patched after the data
        b.u32(zip64 ? 0xFFFF_FFFF : 0); b.u32(zip64 ? 0xFFFF_FFFF : 0)
        b.u16(UInt16(nameBytes.count)); b.u16(zip64 ? 20 : 0)
        b.raw(nameBytes)
        if zip64 { b.u16(ZipFormat.zip64ExtraID); b.u16(16); b.u64(0); b.u64(0) }
        try write(b.bytes)
    }

    private func writeEntry(name: String, modified: Date, method: UInt16, knownSize: UInt64,
                            produce: ((([UInt8]) throws(ZipError) -> Void)) throws(ZipError) -> Void) throws(ZipError) {
        guard !finished else { throw .io("The archive is already finished.") }
        let (nameBytes, flags) = encodedName(name)
        let (t, d) = ZipFormat.dosDateTime(modified)
        let zip64 = forceZip64 || knownSize >= ZipWriter.zip64Threshold
        let offset = position
        try writeLocalHeader(nameBytes: nameBytes, flags: flags, method: method, time: t, date: d, zip64: zip64)
        var crc: UInt32 = 0
        var usize: UInt64 = 0
        let dataStart = position
        let codec: RawDeflateCodec?
        if method == 8 {
            do { codec = try RawDeflateCodec(encode: true) } catch { throw .io("Could not start compression") }
        } else {
            codec = nil
        }
        var pendingError: ZipError?
        func emit(_ out: UnsafeBufferPointer<UInt8>) {
            guard pendingError == nil else { return }
            do throws(ZipError) { try write(Array(out)) } catch { pendingError = error }
        }
        try produce { (chunk: [UInt8]) throws(ZipError) in
            crc = CRC32.checksum(chunk, seed: crc)
            usize += UInt64(chunk.count)
            if let codec {
                do {
                    try chunk.withUnsafeBytes { raw in _ = try codec.process(raw, finalize: false) { emit($0) } }
                } catch {
                    throw ZipError.io("Compression failed for \(name)")
                }
            } else {
                chunk.withUnsafeBufferPointer { emit($0) }
            }
            if let pendingError { throw pendingError }
        }
        if let codec {
            let empty: [UInt8] = []
            do {
                try empty.withUnsafeBytes { raw in _ = try codec.process(raw, finalize: true) { emit($0) } }
            } catch {
                throw .io("Compression failed for \(name)")
            }
            if let pendingError { throw pendingError }
        }
        let csize = position - dataStart
        guard zip64 || (csize < 0xFFFF_FFFF && usize < 0xFFFF_FFFF) else {
            throw .unsupported("\(name) grew beyond 4 GiB without a Zip64 header")
        }
        // Patch CRC and sizes in the local header.
        var patch = ZipBytes()
        patch.u32(crc)
        patch.u32(zip64 ? 0xFFFF_FFFF : UInt32(csize))
        patch.u32(zip64 ? 0xFFFF_FFFF : UInt32(usize))
        do {
            try handle.seek(toOffset: offset + 14)
            try handle.write(contentsOf: patch.bytes)
            if zip64 {
                var z = ZipBytes(); z.u64(usize); z.u64(csize)
                try handle.seek(toOffset: offset + 30 + UInt64(nameBytes.count) + 4)
                try handle.write(contentsOf: z.bytes)
            }
            try handle.seek(toOffset: position)
        } catch {
            throw .io(error.localizedDescription)
        }
        records.append(Record(nameBytes: nameBytes, flags: flags, method: method, time: t, date: d, crc: crc,
                              csize: csize, usize: usize, offset: offset, zip64Local: zip64, isDirectory: false))
    }
}
