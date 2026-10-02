// Spec: 10 §X.4.2 (elements matched by local name, external entities never resolved, malformed XML = corrupt
//       workbook, VESSEL-302), §X.7.2 (one pass per part; a 2 524 × 16 sheet well under 200 ms), VESSEL-312
//       (the XML end-of-line rule: literal CR / CRLF → LF; `&#13;` survives as CR).
// A small, strict, allocation-light pull parser for the OOXML parts of an .xlsx package (faster than XMLParser for
// the ~40 000 `<c>` elements of a large sheet). It checks well-formedness (one root, matching end tags, known
// entities) and never expands a DTD.
import Foundation

struct SvcXmlScanner {
    enum Event {
        /// Local name (prefix stripped) and the attributes as (qualified name, value) pairs.
        case start(name: String, attributes: [(name: String, value: String)])
        case end(name: String)
        /// Character data (entities decoded, line ends normalised); CDATA sections arrive as text too.
        case text(String)
    }

    private let b: [UInt8]
    private var p = 0
    private var stack: [String] = []
    private var rootSeen = false
    private var pendingEnd: String?

    init(_ data: Data) throws(XlsxReadError) {
        var bytes = [UInt8](data)
        if bytes.count >= 2, (bytes[0] == 0xFF && bytes[1] == 0xFE) || (bytes[0] == 0xFE && bytes[1] == 0xFF) {
            let little = bytes[0] == 0xFF
            var units: [UInt16] = []
            units.reserveCapacity(bytes.count / 2)
            var k = 2
            while k + 1 < bytes.count {
                units.append(little ? UInt16(bytes[k]) | UInt16(bytes[k + 1]) << 8
                                    : UInt16(bytes[k]) << 8 | UInt16(bytes[k + 1]))
                k += 2
            }
            bytes = Array(String(decoding: units, as: UTF16.self).utf8)
        } else if bytes.count >= 3, bytes[0] == 0xEF, bytes[1] == 0xBB, bytes[2] == 0xBF {
            bytes.removeFirst(3)
        }
        b = bytes
    }

    /// The local part of a qualified name (`x:c` → `c`).
    static func local(_ q: String) -> String {
        guard let k = q.lastIndex(of: ":") else { return q }
        return String(q[q.index(after: k)...])
    }

    private func fail(_ what: String) -> XlsxReadError { .corrupt(detail: "Malformed XML (\(what) at byte \(p)).") }

    mutating func next() throws(XlsxReadError) -> Event? {
        if let e = pendingEnd {
            pendingEnd = nil
            stack.removeLast()
            return .end(name: Self.local(e))
        }
        while true {
            guard p < b.count else {
                if !stack.isEmpty { throw fail("unclosed element <\(stack.last ?? "")>") }
                if !rootSeen { throw fail("no root element") }
                return nil
            }
            if b[p] != 0x3C {                                                   // character data
                let start = p
                while p < b.count && b[p] != 0x3C { p += 1 }
                if stack.isEmpty {
                    for k in start..<p where !Self.isSpace(b[k]) { throw fail("text outside the root element") }
                    continue
                }
                return .text(try decodeText(start, p))
            }
            if has("<?") { try skip(past: "?>"); continue }
            if has("<!--") { try skip(past: "-->"); continue }
            if has("<![CDATA[") {
                guard !stack.isEmpty else { throw fail("CDATA outside the root element") }
                let start = p + 9
                guard let end = find("]]>", from: start) else { throw fail("unterminated CDATA") }
                p = end + 3
                return .text(Self.normaliseEOL(String(decoding: b[start..<end], as: UTF8.self)))
            }
            if has("<!") { try skipDoctype(); continue }
            if has("</") {
                p += 2
                let name = readName()
                skipSpaces()
                guard p < b.count, b[p] == 0x3E else { throw fail("bad end tag") }
                p += 1
                guard let open = stack.last, open == name else { throw fail("mismatched end tag </\(name)>") }
                stack.removeLast()
                return .end(name: Self.local(name))
            }
            p += 1                                                              // start tag
            let name = readName()
            guard !name.isEmpty else { throw fail("empty element name") }
            var attributes: [(name: String, value: String)] = []
            var selfClosing = false
            while true {
                skipSpaces()
                guard p < b.count else { throw fail("unterminated start tag") }
                if b[p] == 0x3E { p += 1; break }
                if b[p] == 0x2F {
                    guard p + 1 < b.count, b[p + 1] == 0x3E else { throw fail("bad empty-element tag") }
                    p += 2
                    selfClosing = true
                    break
                }
                let attr = readName()
                guard !attr.isEmpty else { throw fail("bad attribute") }
                skipSpaces()
                guard p < b.count, b[p] == 0x3D else { throw fail("attribute without value") }
                p += 1
                skipSpaces()
                guard p < b.count, b[p] == 0x22 || b[p] == 0x27 else { throw fail("unquoted attribute") }
                let quote = b[p]
                p += 1
                let start = p
                while p < b.count && b[p] != quote { p += 1 }
                guard p < b.count else { throw fail("unterminated attribute") }
                let value = try decodeText(start, p, attribute: true)
                p += 1
                attributes.append((attr, value))
            }
            if stack.isEmpty {
                if rootSeen { throw fail("a second root element") }
                rootSeen = true
            }
            stack.append(name)
            if selfClosing { pendingEnd = name }
            return .start(name: Self.local(name), attributes: attributes)
        }
    }

    // MARK: Lexing helpers

    private static func isSpace(_ c: UInt8) -> Bool { c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D }

    private mutating func skipSpaces() { while p < b.count && Self.isSpace(b[p]) { p += 1 } }

    private mutating func readName() -> String {
        let start = p
        while p < b.count {
            let c = b[p]
            if Self.isSpace(c) || c == 0x3E || c == 0x2F || c == 0x3D { break }
            p += 1
        }
        return String(decoding: b[start..<p], as: UTF8.self)
    }

    private func has(_ s: StaticString) -> Bool {
        let n = s.utf8CodeUnitCount
        guard p + n <= b.count else { return false }
        return s.withUTF8Buffer { buf in
            for k in 0..<n where b[p + k] != buf[k] { return false }
            return true
        }
    }

    private func find(_ s: StaticString, from: Int) -> Int? {
        let n = s.utf8CodeUnitCount
        return s.withUTF8Buffer { buf -> Int? in
            var k = from
            while k + n <= b.count {
                if b[k] == buf[0] {
                    var ok = true
                    for j in 1..<n where b[k + j] != buf[j] { ok = false; break }
                    if ok { return k }
                }
                k += 1
            }
            return nil
        }
    }

    private mutating func skip(past s: StaticString) throws(XlsxReadError) {
        guard let k = find(s, from: p + 1) else { throw fail("unterminated markup") }
        p = k + s.utf8CodeUnitCount
    }

    /// `<!DOCTYPE …>` including an internal subset; never expanded.
    private mutating func skipDoctype() throws(XlsxReadError) {
        var depth = 0
        while p < b.count {
            let c = b[p]
            p += 1
            if c == 0x5B { depth += 1 } else if c == 0x5D { depth -= 1 } else if c == 0x3E && depth <= 0 { return }
        }
        throw fail("unterminated DOCTYPE")
    }

    /// Decodes `b[start..<end]`: the five predefined entities and character references; literal CR/CRLF → LF; in an
    /// attribute value every literal tab / CR / LF becomes a space (XML attribute-value normalisation).
    private func decodeText(_ start: Int, _ end: Int, attribute: Bool = false) throws(XlsxReadError) -> String {
        var simple = true
        for k in start..<end where b[k] == 0x26 || b[k] == 0x0D || (attribute && (b[k] == 0x09 || b[k] == 0x0A)) {
            simple = false
            break
        }
        if simple { return String(decoding: b[start..<end], as: UTF8.self) }
        var out: [UInt8] = []
        out.reserveCapacity(end - start)
        var k = start
        while k < end {
            let c = b[k]
            if c == 0x26 {
                guard let semi = b[k..<end].firstIndex(of: 0x3B) else { throw fail("unterminated entity") }
                let name = String(decoding: b[(k + 1)..<semi], as: UTF8.self)
                switch name {
                case "lt": out.append(0x3C)
                case "gt": out.append(0x3E)
                case "amp": out.append(0x26)
                case "quot": out.append(0x22)
                case "apos": out.append(0x27)
                default:
                    guard name.hasPrefix("#"), let v = Self.charRef(name), let sc = Unicode.Scalar(v),
                          v != 0 else { throw fail("unknown entity &\(name);") }
                    out.append(contentsOf: Array(String(Character(sc)).utf8))
                }
                k = semi + 1
            } else if c == 0x0D {
                out.append(attribute ? 0x20 : 0x0A)
                k += (k + 1 < end && b[k + 1] == 0x0A) ? 2 : 1
            } else if attribute && (c == 0x09 || c == 0x0A) {
                out.append(0x20)
                k += 1
            } else {
                out.append(c)
                k += 1
            }
        }
        return String(decoding: out, as: UTF8.self)
    }

    private static func charRef(_ name: String) -> UInt32? {
        let body = name.dropFirst()
        if body.hasPrefix("x") { return UInt32(body.dropFirst(), radix: 16) }
        return UInt32(body, radix: 10)
    }

    static func normaliseEOL(_ s: String) -> String {
        guard s.unicodeScalars.contains("\r") else { return s }
        return s.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
    }
}
