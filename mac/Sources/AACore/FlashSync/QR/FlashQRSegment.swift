// Spec: 13 §3.10, §6.3 / FLASH-071 (Base45 text → alphanumeric mode). Part of the pure-Swift port of Project Nayuki's
// QR Code generator library (https://www.nayuki.io/page/qr-code-generator-library, MIT License,
// Copyright (c) Project Nayuki) — the algorithm Windows uses through Net.Codecrete.QrCodeGenerator. Structure and
// behaviour follow `qrcodegen.py` 1.8.0 so the module matrices are bit-identical.

/// An append-only sequence of bits.
public struct FlashQRBitBuffer: Sendable, Equatable {
    public private(set) var bits: [Bool] = []

    public init() {}

    public var count: Int { bits.count }

    /// Appends the low `length` bits of `value`, most significant first.
    public mutating func append(_ value: Int, bits length: Int) {
        precondition(length >= 0 && length <= 31 && value >> length == 0, "value out of range")
        var i = length - 1
        while i >= 0 {
            bits.append((value >> i) & 1 != 0)
            i -= 1
        }
    }

    public mutating func append(contentsOf other: FlashQRBitBuffer) { bits += other.bits }
}

/// A segment of character/binary data in a QR symbol.
public struct FlashQRSegment: Sendable, Equatable {
    public enum Mode: Sendable, Equatable {
        case numeric, alphanumeric, byte

        var modeBits: Int {
            switch self {
            case .numeric: return 0x1
            case .alphanumeric: return 0x2
            case .byte: return 0x4
            }
        }

        /// Character-count bits for a version (1–9 / 10–26 / 27–40).
        public func charCountBits(version: Int) -> Int {
            let i = (version + 7) / 17
            switch self {
            case .numeric: return [10, 12, 14][i]
            case .alphanumeric: return [9, 11, 13][i]
            case .byte: return [8, 16, 16][i]
            }
        }
    }

    public let mode: Mode
    public let numChars: Int
    public let data: FlashQRBitBuffer

    public init(mode: Mode, numChars: Int, data: FlashQRBitBuffer) {
        self.mode = mode
        self.numChars = numChars
        self.data = data
    }

    /// QR's alphanumeric character set — exactly the Base45 alphabet.
    public static let alphanumericCharset: [UInt8] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ $%*+-./:".utf8)

    private static let alphanumericIndex: [Int8] = {
        var t = [Int8](repeating: -1, count: 128)
        for (i, c) in alphanumericCharset.enumerated() { t[Int(c)] = Int8(i) }
        return t
    }()

    public static func isNumeric(_ text: String) -> Bool { text.utf8.allSatisfy { $0 >= 0x30 && $0 <= 0x39 } }

    public static func isAlphanumeric(_ text: String) -> Bool {
        text.utf8.allSatisfy { $0 < 128 && alphanumericIndex[Int($0)] >= 0 }
    }

    public static func makeBytes(_ data: [UInt8]) -> FlashQRSegment {
        var bb = FlashQRBitBuffer()
        for b in data { bb.append(Int(b), bits: 8) }
        return FlashQRSegment(mode: .byte, numChars: data.count, data: bb)
    }

    /// Digits in groups of three (10 bits), a 2-digit tail in 7 bits, a 1-digit tail in 4 bits.
    public static func makeNumeric(_ digits: String) -> FlashQRSegment {
        precondition(isNumeric(digits), "String contains non-numeric characters")
        let d = Array(digits.utf8).map { Int($0) - 0x30 }
        var bb = FlashQRBitBuffer()
        var i = 0
        while i < d.count {
            let n = min(d.count - i, 3)
            var v = 0
            for j in 0 ..< n { v = v * 10 + d[i + j] }
            bb.append(v, bits: n * 3 + 1)
            i += n
        }
        return FlashQRSegment(mode: .numeric, numChars: d.count, data: bb)
    }

    /// Pairs as `first·45 + second` in 11 bits, a single tail character in 6 bits.
    public static func makeAlphanumeric(_ text: String) -> FlashQRSegment {
        precondition(isAlphanumeric(text), "String contains unencodable characters in alphanumeric mode")
        let c = Array(text.utf8).map { Int(alphanumericIndex[Int($0)]) }
        var bb = FlashQRBitBuffer()
        var i = 0
        while i + 1 < c.count {
            bb.append(c[i] * 45 + c[i + 1], bits: 11)
            i += 2
        }
        if c.count % 2 == 1 { bb.append(c[c.count - 1], bits: 6) }
        return FlashQRSegment(mode: .alphanumeric, numChars: c.count, data: bb)
    }

    /// Nayuki `make_segments`: none for "", numeric if all digits, alphanumeric if every character is in the
    /// charset, otherwise UTF-8 bytes.
    public static func makeSegments(_ text: String) -> [FlashQRSegment] {
        if text.isEmpty { return [] }
        if isNumeric(text) { return [makeNumeric(text)] }
        if isAlphanumeric(text) { return [makeAlphanumeric(text)] }
        return [makeBytes(Array(text.utf8))]
    }

    /// Total bits for these segments at a version, or nil when a character count overflows its field.
    public static func totalBits(_ segs: [FlashQRSegment], version: Int) -> Int? {
        var result = 0
        for seg in segs {
            let ccbits = seg.mode.charCountBits(version: version)
            if seg.numChars >= 1 << ccbits { return nil }
            result += 4 + ccbits + seg.data.count
        }
        return result
    }
}
