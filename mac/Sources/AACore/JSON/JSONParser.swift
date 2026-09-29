// Spec: 01 §4.1.4, §4.1.8 (framing, BOM, no comments/trailing commas), §4.1.9 (depth 64), §3.4 (invalid UTF-8
//       → U+FFFD), App. A19/A09b; ARCHITECTURE.md §3.2.
import Foundation

public enum JSONParseError: Error, Equatable, Sendable, CustomStringConvertible {
    case invalid(offset: Int, reason: String)      // comments, trailing commas, bad literal, NaN, trailing content…
    case tooDeep(limit: Int)                       // > 64 (01 §4.1.9)
    case invalidUTF8(offset: Int)                  // only with `invalidUTF8: .reject`

    public var description: String {
        switch self {
        case let .invalid(offset, reason): return "Invalid JSON at byte \(offset): \(reason)"
        case let .tooDeep(limit): return "The JSON is nested deeper than \(limit) levels."
        case let .invalidUTF8(offset): return "Invalid UTF-8 at byte \(offset)"
        }
    }
}

public enum InvalidUTF8Policy: Sendable { case replace, reject }

public enum JSONParser {
    public static let maxDepth = 64

    /// Byte-level UTF-8 parser. A leading UTF-8 BOM is skipped. Keeps key order and number lexemes.
    /// `.replace` (default) decodes invalid UTF-8 sequences as U+FFFD like .NET `Encoding.UTF8.GetString`.
    public static func parse(_ data: Data, maxDepth: Int = maxDepth,
                             invalidUTF8: InvalidUTF8Policy = .replace) throws(JSONParseError) -> JSONValue {
        var bytes = [UInt8](data)
        if bytes.count >= 3, bytes[0] == 0xEF, bytes[1] == 0xBB, bytes[2] == 0xBF { bytes.removeFirst(3) }
        if let bad = firstInvalidUTF8(bytes) {
            switch invalidUTF8 {
            case .reject: throw .invalidUTF8(offset: bad)
            case .replace: bytes = Array(String(decoding: bytes, as: UTF8.self).utf8)
            }
        }
        return try parseValidUTF8(bytes, maxDepth: maxDepth)
    }

    public static func parse(_ text: String, maxDepth: Int = maxDepth) throws(JSONParseError) -> JSONValue {
        var bytes = Array(text.utf8)
        if bytes.count >= 3, bytes[0] == 0xEF, bytes[1] == 0xBB, bytes[2] == 0xBF { bytes.removeFirst(3) }
        return try parseValidUTF8(bytes, maxDepth: maxDepth)
    }

    static func parseValidUTF8(_ bytes: [UInt8], maxDepth: Int) throws(JSONParseError) -> JSONValue {
        do {
            return try bytes.withUnsafeBufferPointer { buf in
                var p = Impl(buf: buf, maxDepth: maxDepth)
                return try p.document()
            }
        } catch let e as JSONParseError {
            throw e
        } catch {
            throw .invalid(offset: 0, reason: "\(error)")
        }
    }

    /// Offset of the first byte that starts an invalid UTF-8 sequence, or nil when valid.
    static func firstInvalidUTF8(_ b: [UInt8]) -> Int? {
        var i = 0
        let n = b.count
        while i < n {
            let c = b[i]
            if c < 0x80 { i += 1; continue }
            var need = 0
            var lo: UInt8 = 0x80, hi: UInt8 = 0xBF
            switch c {
            case 0xC2...0xDF: need = 1
            case 0xE0: need = 2; lo = 0xA0
            case 0xE1...0xEC, 0xEE...0xEF: need = 2
            case 0xED: need = 2; hi = 0x9F
            case 0xF0: need = 3; lo = 0x90
            case 0xF1...0xF3: need = 3
            case 0xF4: need = 3; hi = 0x8F
            default: return i
            }
            guard i + need < n else { return i }
            let c1 = b[i + 1]
            guard c1 >= lo, c1 <= hi else { return i }
            for k in 2..<(need + 1) where b[i + k] < 0x80 || b[i + k] > 0xBF { return i }
            i += need + 1
        }
        return nil
    }

    struct Impl {
        let buf: UnsafeBufferPointer<UInt8>
        let maxDepth: Int
        var i = 0
        var depth = 0

        init(buf: UnsafeBufferPointer<UInt8>, maxDepth: Int) { self.buf = buf; self.maxDepth = maxDepth }

        func fail(_ reason: String, at offset: Int? = nil) -> JSONParseError {
            .invalid(offset: offset ?? i, reason: reason)
        }

        mutating func skipWhitespace() {
            while i < buf.count {
                let c = buf[i]
                if c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D { i += 1 } else { return }
            }
        }

        mutating func document() throws(JSONParseError) -> JSONValue {
            skipWhitespace()
            guard i < buf.count else { throw fail("empty input") }
            let v = try value()
            skipWhitespace()
            guard i == buf.count else { throw fail("unexpected trailing content") }
            return v
        }

        mutating func value() throws(JSONParseError) -> JSONValue {
            guard i < buf.count else { throw fail("unexpected end of input") }
            switch buf[i] {
            case 0x7B: return try object()
            case 0x5B: return try array()
            case 0x22: return .string(try string())
            case 0x74: try literal("true"); return .bool(true)
            case 0x66: try literal("false"); return .bool(false)
            case 0x6E: try literal("null"); return .null
            case 0x2D, 0x30...0x39: return .number(try number())
            case 0x2F: throw fail("comments are not allowed")
            default: throw fail("unexpected character")
            }
        }

        mutating func literal(_ word: StaticString) throws(JSONParseError) {
            let n = word.utf8CodeUnitCount
            guard i + n <= buf.count else { throw fail("invalid literal") }
            let p = word.utf8Start
            for k in 0..<n where buf[i + k] != p[k] { throw fail("invalid literal") }
            i += n
        }

        mutating func enter() throws(JSONParseError) {
            depth += 1
            if depth > maxDepth { throw .tooDeep(limit: maxDepth) }
        }

        mutating func object() throws(JSONParseError) -> JSONValue {
            try enter()
            i += 1
            var obj = JSONObject()
            skipWhitespace()
            if i < buf.count, buf[i] == 0x7D { i += 1; depth -= 1; return .object(obj) }
            while true {
                skipWhitespace()
                guard i < buf.count else { throw fail("unterminated object") }
                guard buf[i] == 0x22 else {
                    throw fail(buf[i] == 0x7D ? "trailing comma" : (buf[i] == 0x2F ? "comments are not allowed" : "expected a property name"))
                }
                let key = try string()
                skipWhitespace()
                guard i < buf.count, buf[i] == 0x3A else { throw fail("expected ':'") }
                i += 1
                skipWhitespace()
                let v = try value()
                obj.set(key, v)                                  // first position, last value
                skipWhitespace()
                guard i < buf.count else { throw fail("unterminated object") }
                if buf[i] == 0x2C { i += 1; continue }
                if buf[i] == 0x7D { i += 1; break }
                throw fail("expected ',' or '}'")
            }
            depth -= 1
            return .object(obj)
        }

        mutating func array() throws(JSONParseError) -> JSONValue {
            try enter()
            i += 1
            var items: [JSONValue] = []
            skipWhitespace()
            if i < buf.count, buf[i] == 0x5D { i += 1; depth -= 1; return .array(items) }
            while true {
                skipWhitespace()
                guard i < buf.count else { throw fail("unterminated array") }
                if buf[i] == 0x5D { throw fail("trailing comma") }
                items.append(try value())
                skipWhitespace()
                guard i < buf.count else { throw fail("unterminated array") }
                if buf[i] == 0x2C { i += 1; continue }
                if buf[i] == 0x5D { i += 1; break }
                throw fail("expected ',' or ']'")
            }
            depth -= 1
            return .array(items)
        }

        mutating func number() throws(JSONParseError) -> JSONNumber {
            let start = i
            if buf[i] == 0x2D { i += 1 }
            guard i < buf.count, buf[i] >= 0x30, buf[i] <= 0x39 else { throw fail("invalid number", at: start) }
            if buf[i] == 0x30 {
                i += 1
            } else {
                while i < buf.count, buf[i] >= 0x30, buf[i] <= 0x39 { i += 1 }
            }
            if i < buf.count, buf[i] == 0x2E {
                i += 1
                guard i < buf.count, buf[i] >= 0x30, buf[i] <= 0x39 else { throw fail("invalid number", at: start) }
                while i < buf.count, buf[i] >= 0x30, buf[i] <= 0x39 { i += 1 }
            }
            if i < buf.count, buf[i] == 0x65 || buf[i] == 0x45 {
                i += 1
                if i < buf.count, buf[i] == 0x2B || buf[i] == 0x2D { i += 1 }
                guard i < buf.count, buf[i] >= 0x30, buf[i] <= 0x39 else { throw fail("invalid number", at: start) }
                while i < buf.count, buf[i] >= 0x30, buf[i] <= 0x39 { i += 1 }
            }
            return JSONNumber(lexeme: String(decoding: UnsafeBufferPointer(rebasing: buf[start..<i]), as: UTF8.self))
        }

        mutating func hex4() throws(JSONParseError) -> UInt32 {
            guard i + 4 <= buf.count else { throw fail("invalid \\u escape") }
            var v: UInt32 = 0
            for _ in 0..<4 {
                let c = buf[i]
                let d: UInt32
                switch c {
                case 0x30...0x39: d = UInt32(c - 0x30)
                case 0x41...0x46: d = UInt32(c - 0x41 + 10)
                case 0x61...0x66: d = UInt32(c - 0x61 + 10)
                default: throw fail("invalid \\u escape")
                }
                v = v * 16 + d
                i += 1
            }
            return v
        }

        mutating func string() throws(JSONParseError) -> String {
            i += 1                                                // opening quote
            let start = i
            // Fast path: no escapes.
            while i < buf.count {
                let c = buf[i]
                if c == 0x22 {
                    let s = String(decoding: UnsafeBufferPointer(rebasing: buf[start..<i]), as: UTF8.self)
                    i += 1
                    return s
                }
                if c == 0x5C { break }
                if c < 0x20 { throw fail("control character in string") }
                i += 1
            }
            var out = [UInt8](UnsafeBufferPointer(rebasing: buf[start..<i]))
            while i < buf.count {
                let c = buf[i]
                if c == 0x22 { i += 1; return String(decoding: out, as: UTF8.self) }
                if c < 0x20 { throw fail("control character in string") }
                if c != 0x5C { out.append(c); i += 1; continue }
                i += 1
                guard i < buf.count else { break }
                let e = buf[i]
                i += 1
                switch e {
                case 0x22: out.append(0x22)
                case 0x5C: out.append(0x5C)
                case 0x2F: out.append(0x2F)
                case 0x62: out.append(0x08)
                case 0x66: out.append(0x0C)
                case 0x6E: out.append(0x0A)
                case 0x72: out.append(0x0D)
                case 0x74: out.append(0x09)
                case 0x75:
                    var scalarValue = try hex4()
                    if (0xD800...0xDBFF).contains(scalarValue) {
                        // A high surrogate must be followed by \uDC00…\uDFFF; a lone surrogate becomes U+FFFD
                        // (a Swift String cannot hold it; documented divergence A09b).
                        if i + 6 <= buf.count, buf[i] == 0x5C, buf[i + 1] == 0x75 {
                            let save = i
                            i += 2
                            let low = try hex4()
                            if (0xDC00...0xDFFF).contains(low) {
                                scalarValue = 0x10000 + ((scalarValue - 0xD800) << 10) + (low - 0xDC00)
                            } else {
                                scalarValue = 0xFFFD
                                i = save
                            }
                        } else {
                            scalarValue = 0xFFFD
                        }
                    } else if (0xDC00...0xDFFF).contains(scalarValue) {
                        scalarValue = 0xFFFD
                    }
                    let scalar = Unicode.Scalar(scalarValue) ?? "\u{FFFD}"
                    UTF8.encode(scalar) { out.append($0) }
                default:
                    throw fail("invalid escape", at: i - 1)
                }
            }
            throw fail("unterminated string")
        }
    }
}
