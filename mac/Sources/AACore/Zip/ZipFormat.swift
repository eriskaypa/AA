// Spec: 01 §4.5 (bundle layout), §6.7 (Deflate+Stored, Zip64, data descriptors, UTF-8 flag / CP437 names,
//       security rules), 09 §3.10 (XLSX packages use the same writer); ARCHITECTURE.md §6.4.
import Foundation

public enum ZipError: Error, Sendable, Equatable, LocalizedError {
    case notAZip, corrupt(String), unsafePath(String), crcMismatch(String), unsupported(String), io(String)

    public var errorDescription: String? {
        switch self {
        case .notAZip: return "The file is not a ZIP archive."
        case .corrupt(let s): return "The ZIP archive is damaged (\(s))."
        case .unsafePath(let s): return "The ZIP archive contains an unsafe entry name: \(s)"
        case .crcMismatch(let s): return "The ZIP entry \(s) is damaged (checksum mismatch)."
        case .unsupported(let s): return "The ZIP archive uses an unsupported feature: \(s)"
        case .io(let s): return s
        }
    }
}

public struct ZipEntryInfo: Sendable, Hashable {
    public let name: String
    public let isDirectory: Bool
    public let method: UInt16
    public let compressedSize: UInt64
    public let uncompressedSize: UInt64
    public let crc32: UInt32
    public let modified: Date?
    public let isUTF8: Bool
    /// Offset of the entry's local header (additive; used by the reader).
    public let localHeaderOffset: UInt64

    public init(name: String, isDirectory: Bool, method: UInt16, compressedSize: UInt64, uncompressedSize: UInt64,
                crc32: UInt32, modified: Date?, isUTF8: Bool, localHeaderOffset: UInt64 = 0) {
        self.name = name; self.isDirectory = isDirectory; self.method = method; self.compressedSize = compressedSize
        self.uncompressedSize = uncompressedSize; self.crc32 = crc32; self.modified = modified; self.isUTF8 = isUTF8
        self.localHeaderOffset = localHeaderOffset
    }
}

enum ZipFormat {
    static let localSig: UInt32 = 0x0403_4B50
    static let centralSig: UInt32 = 0x0201_4B50
    static let eocdSig: UInt32 = 0x0605_4B50
    static let zip64EocdSig: UInt32 = 0x0606_4B50
    static let zip64LocatorSig: UInt32 = 0x0706_4B50
    static let dataDescriptorSig: UInt32 = 0x0807_4B50
    static let flagDataDescriptor: UInt16 = 1 << 3
    static let flagUTF8: UInt16 = 1 << 11
    static let zip64ExtraID: UInt16 = 0x0001
    static let unicodePathExtraID: UInt16 = 0x7075

    /// MS-DOS date/time (local time) ⇄ Date.
    static func dosDateTime(_ date: Date) -> (time: UInt16, date: UInt16) {
        let c = Calendar(identifier: .gregorian).dateComponents(in: .current, from: date)
        let y = max(1980, min(2107, c.year ?? 1980))
        let t = UInt16((c.hour ?? 0) << 11 | (c.minute ?? 0) << 5 | (c.second ?? 0) / 2)
        let d = UInt16((y - 1980) << 9 | (c.month ?? 1) << 5 | (c.day ?? 1))
        return (t, d)
    }

    static func date(dosTime: UInt16, dosDate: UInt16) -> Date? {
        var c = DateComponents()
        c.year = Int(dosDate >> 9) + 1980
        c.month = Int((dosDate >> 5) & 0xF)
        c.day = Int(dosDate & 0x1F)
        c.hour = Int(dosTime >> 11)
        c.minute = Int((dosTime >> 5) & 0x3F)
        c.second = Int(dosTime & 0x1F) * 2
        guard let m = c.month, (1...12).contains(m), let d = c.day, d >= 1 else { return nil }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        return cal.date(from: c)
    }

    /// Code page 437, bytes 0x80…0xFF.
    static let cp437High: [Unicode.Scalar] = [
        "Ç", "ü", "é", "â", "ä", "à", "å", "ç", "ê", "ë", "è", "ï", "î", "ì", "Ä", "Å",
        "É", "æ", "Æ", "ô", "ö", "ò", "û", "ù", "ÿ", "Ö", "Ü", "¢", "£", "¥", "₧", "ƒ",
        "á", "í", "ó", "ú", "ñ", "Ñ", "ª", "º", "¿", "⌐", "¬", "½", "¼", "¡", "«", "»",
        "░", "▒", "▓", "│", "┤", "╡", "╢", "╖", "╕", "╣", "║", "╗", "╝", "╜", "╛", "┐",
        "└", "┴", "┬", "├", "─", "┼", "╞", "╟", "╚", "╔", "╩", "╦", "╠", "═", "╬", "╧",
        "╨", "╤", "╥", "╙", "╘", "╒", "╓", "╫", "╪", "┘", "┌", "█", "▄", "▌", "▐", "▀",
        "α", "ß", "Γ", "π", "Σ", "σ", "µ", "τ", "Φ", "Θ", "Ω", "δ", "∞", "φ", "ε", "∩",
        "≡", "±", "≥", "≤", "⌠", "⌡", "÷", "≈", "°", "∙", "·", "√", "ⁿ", "²", "■", "\u{00A0}",
    ]

    static func decodeName(_ bytes: [UInt8], utf8: Bool) -> String {
        if utf8 || bytes.allSatisfy({ $0 < 0x80 }) { return String(decoding: bytes, as: UTF8.self) }
        var s = String.UnicodeScalarView()
        for b in bytes { s.append(b < 0x80 ? Unicode.Scalar(b) : cp437High[Int(b) - 0x80]) }
        return String(s)
    }

    /// Normalised relative path of an entry for extraction, or nil when unsafe (absolute, drive-qualified, `..`).
    /// Backslashes are treated as separators (Windows semantics).
    static func safeRelativePath(_ name: String) -> String? {
        let n = name.replacingOccurrences(of: "\\", with: "/")
        if n.hasPrefix("/") { return nil }
        let u = Array(n.utf8)
        if u.count >= 2, u[1] == 0x3A { return nil }               // C:…
        var parts: [String] = []
        for comp in n.split(separator: "/", omittingEmptySubsequences: true) {
            if comp == "." { continue }
            if comp == ".." { return nil }
            parts.append(String(comp))
        }
        if parts.isEmpty { return nil }
        return parts.joined(separator: "/") + (n.hasSuffix("/") ? "/" : "")
    }
}

/// Little-endian byte building / reading helpers.
struct ZipBytes {
    var bytes: [UInt8] = []
    mutating func u16(_ v: UInt16) { bytes.append(UInt8(v & 0xFF)); bytes.append(UInt8(v >> 8)) }
    mutating func u32(_ v: UInt32) { for i in 0..<4 { bytes.append(UInt8((v >> (8 * UInt32(i))) & 0xFF)) } }
    mutating func u64(_ v: UInt64) { for i in 0..<8 { bytes.append(UInt8((v >> (8 * UInt64(i))) & 0xFF)) } }
    mutating func raw(_ b: [UInt8]) { bytes.append(contentsOf: b) }
}

struct ZipReadCursor {
    let b: [UInt8]
    var i: Int
    init(_ b: [UInt8], _ i: Int = 0) { self.b = b; self.i = i }
    var remaining: Int { b.count - i }
    mutating func u16() throws(ZipError) -> UInt16 {
        guard i + 2 <= b.count else { throw .corrupt("truncated header") }
        defer { i += 2 }
        return UInt16(b[i]) | UInt16(b[i + 1]) << 8
    }
    mutating func u32() throws(ZipError) -> UInt32 {
        guard i + 4 <= b.count else { throw .corrupt("truncated header") }
        defer { i += 4 }
        return UInt32(b[i]) | UInt32(b[i + 1]) << 8 | UInt32(b[i + 2]) << 16 | UInt32(b[i + 3]) << 24
    }
    mutating func u64() throws(ZipError) -> UInt64 {
        let lo = UInt64(try u32()), hi = UInt64(try u32())
        return lo | hi << 32
    }
    mutating func take(_ n: Int) throws(ZipError) -> [UInt8] {
        guard n >= 0, i + n <= b.count else { throw .corrupt("truncated header") }
        defer { i += n }
        return Array(b[i..<(i + n)])
    }
}
