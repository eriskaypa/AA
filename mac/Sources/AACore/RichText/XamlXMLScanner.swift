// Spec: 05 §XD.2.1 steps 1–4 (parse pipeline: BOM, declaration, DTD, namespaces, malformed XML), §XD.5 (hand-written
//       XML 1.0 tokenizer with UTF-16 source ranges, five predefined entities plus character references, undefined
//       entities rejected, end-of-line and attribute-value normalisation; budget 1 MB parse + resolve < 50 ms),
//       §4.3.1 (reading tolerance).
// Phase 1 of `XamlDOM.parse`: a strict, namespace-aware XML reader that produces a raw element tree whose every
// element knows its exact UTF-16 range in the source (byte-for-byte opaque preservation, §4.3.7 rule 10). It reads
// the UTF-8 bytes (Swift strings are always valid UTF-8) and keeps a running UTF-16 offset.
import Foundation

/// One attribute exactly as read (after entity decoding and attribute-value normalisation).
struct XamlRawXMLAttribute {
    var qualifiedName: String
    var prefix: String?
    var localName: String
    var namespaceURI: String?
    var value: String
    var isNamespaceDeclaration: Bool
}

/// A child of a raw element: an element (index into `XamlRawXMLTree.elements`) or character data.
enum XamlRawXMLChild {
    case element(Int)
    /// Decoded text (CDATA included), its UTF-16 source range, and whether it came from CDATA.
    case text(String, Range<Int>, isCData: Bool)
}

struct XamlRawXMLElement {
    var qualifiedName: String
    var prefix: String?
    var localName: String
    var namespaceURI: String?
    var attributes: [XamlRawXMLAttribute]
    var children: [XamlRawXMLChild]
    /// Whole element (UTF-16): from `<` of the start tag to the end of the end tag (or of the empty-element tag).
    var range: Range<Int>
    /// Content between the start tag and the end tag (empty for `<X/>`).
    var contentRange: Range<Int>
    var parent: Int?
}

struct XamlRawXMLTree {
    var elements: [XamlRawXMLElement]
    var root: Int
}

enum XamlXMLNamespaces {
    static let presentation = "http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    static let xaml = "http://schemas.microsoft.com/winfx/2006/xaml"
    static let xml = "http://www.w3.org/XML/1998/namespace"
    static let xmlns = "http://www.w3.org/2000/xmlns/"
}

/// Strict XML 1.0 (with namespaces) scanner over UTF-8 bytes.
struct XamlXMLScanner {
    private let b: [UInt8]
    private var i: Int = 0
    /// UTF-16 offset of byte `i`.
    private var p16: Int = 0
    private var elements: [XamlRawXMLElement] = []
    /// Namespace scopes: prefix ("" = default) → URI, innermost last.
    private var scopes: [[String: String]] = []
    private let depthLimit = 2_000

    init(bytes: [UInt8]) { self.b = bytes }

    struct Failure: Error { let fatal: XamlFatalError }

    static func scan(_ source: String) -> Result<XamlRawXMLTree, XamlFatalError> {
        var s = XamlXMLScanner(bytes: Array(source.utf8))
        do { return .success(try s.document()) } catch let f as Failure { return .failure(f.fatal) } catch {
            return .failure(.malformedXML("\(error)"))
        }
    }

    /// Compatibility entry for callers holding UTF-16 code units.
    static func scan(_ units: [UInt16]) -> Result<XamlRawXMLTree, XamlFatalError> {
        scan(String(decoding: units, as: UTF16.self))
    }

    // MARK: - Errors

    private func malformed(_ what: String) -> Failure {
        var line = 1, col = 1, k = 0
        while k < min(i, b.count) {
            if b[k] == 0x0A { line += 1; col = 1 } else if b[k] < 0x80 || b[k] >= 0xC0 { col += 1 }
            k += 1
        }
        return Failure(fatal: .malformedXML("\(what) (line \(line), position \(col))"))
    }

    // MARK: - Cursor

    @inline(__always) private static func width16(_ c: UInt8) -> Int {
        c < 0x80 ? 1 : (c >= 0xF0 ? 2 : (c >= 0xC0 ? 1 : 0))
    }

    /// Advance over ASCII bytes only.
    @inline(__always) private mutating func skipASCII(_ n: Int) { i += n; p16 += n }

    @inline(__always) private mutating func step() {
        p16 += Self.width16(b[i])
        i += 1
    }

    @inline(__always) private static func isSpace(_ c: UInt8) -> Bool { c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D }

    @inline(__always) private static func isNameStart(_ c: UInt8) -> Bool {
        (c >= 0x61 && c <= 0x7A) || (c >= 0x41 && c <= 0x5A) || c == 0x5F || c == 0x3A || c >= 0x80
    }

    @inline(__always) private static func isNameChar(_ c: UInt8) -> Bool {
        isNameStart(c) || (c >= 0x30 && c <= 0x39) || c == 0x2D || c == 0x2E
    }

    private func at(_ s: StaticString) -> Bool {
        let n = s.utf8CodeUnitCount
        guard i + n <= b.count else { return false }
        let p = s.utf8Start
        for k in 0..<n where b[i + k] != p[k] { return false }
        return true
    }

    private mutating func skipSpace() { while i < b.count, Self.isSpace(b[i]) { skipASCII(1) } }

    // MARK: - Document

    private mutating func document() throws -> XamlRawXMLTree {
        if b.count >= 3, b[0] == 0xEF, b[1] == 0xBB, b[2] == 0xBF { i = 3; p16 = 1 }    // XD.2.1 step 1
        skipSpace()
        if at("<?xml"), i + 5 < b.count, Self.isSpace(b[i + 5]) || b[i + 5] == 0x3F { try skipPI() }
        var root: Int?
        while true {
            skipSpace()
            if i >= b.count { break }
            guard b[i] == 0x3C else {
                throw malformed(root == nil ? "Data at the root level is invalid" : "Text after the root element")
            }
            if at("<!--") { try skipComment(); continue }
            if at("<?") { try skipPI(); continue }
            if at("<!DOCTYPE") || at("<!doctype") {
                if root == nil { throw Failure(fatal: .dtdPresent) }                   // XD.2.1 step 2
                throw malformed("Unexpected DTD declaration")
            }
            if at("<!") { throw malformed("Unexpected markup declaration") }
            guard root == nil else { throw malformed("There are multiple root elements") }
            scopes = [["xml": XamlXMLNamespaces.xml]]
            root = try element(parent: nil, depth: 0)
        }
        guard let r = root else { throw malformed("Root element is missing") }
        return XamlRawXMLTree(elements: elements, root: r)
    }

    private mutating func skipComment() throws {
        skipASCII(4)
        while i + 2 < b.count {
            if b[i] == 0x2D, b[i + 1] == 0x2D {
                guard b[i + 2] == 0x3E else { throw malformed("'--' is not allowed inside a comment") }
                skipASCII(3)
                return
            }
            guard b[i] >= 0x20 || b[i] == 0x09 || b[i] == 0x0A || b[i] == 0x0D else {
                throw malformed("Invalid character in a comment")
            }
            step()
        }
        throw malformed("Unexpected end of file in a comment")
    }

    private mutating func skipPI() throws {
        skipASCII(2)
        while i + 1 < b.count {
            if b[i] == 0x3F, b[i + 1] == 0x3E { skipASCII(2); return }
            step()
        }
        throw malformed("Unexpected end of file in a processing instruction")
    }

    // MARK: - Names

    /// A name at `i`: (qualified, prefix, local).
    private mutating func qname() throws -> (String, String?, String) {
        let start = i
        guard i < b.count, Self.isNameStart(b[i]) else { throw malformed("Name expected") }
        var colon = -1
        while i < b.count, Self.isNameChar(b[i]) {
            if b[i] == 0x3A {
                guard colon < 0 else { throw malformed("Invalid qualified name") }
                colon = i
            }
            step()
        }
        let q = String(decoding: b[start..<i], as: UTF8.self)
        guard colon >= 0 else { return (q, nil, q) }
        guard colon > start, colon < i - 1 else { throw malformed("Invalid qualified name '\(q)'") }
        return (q, String(decoding: b[start..<colon], as: UTF8.self), String(decoding: b[(colon + 1)..<i], as: UTF8.self))
    }

    private func resolve(_ prefix: String?) -> String? {
        let key = prefix ?? ""
        for scope in scopes.reversed() { if let v = scope[key] { return v.isEmpty ? nil : v } }
        return nil
    }

    // MARK: - Elements

    private mutating func element(parent: Int?, depth: Int) throws -> Int {
        guard depth < depthLimit else { throw malformed("The document is nested too deeply") }
        let start16 = p16
        skipASCII(1)                                                    // '<'
        let (qn, prefix, local) = try qname()
        var attrs: [XamlRawXMLAttribute] = []
        var selfClosing = false
        while true {
            let hadSpace = i < b.count && Self.isSpace(b[i])
            skipSpace()
            guard i < b.count else { throw malformed("Unexpected end of file in a start tag") }
            if b[i] == 0x3E { skipASCII(1); break }
            if b[i] == 0x2F {
                guard i + 1 < b.count, b[i + 1] == 0x3E else { throw malformed("'/' must be followed by '>'") }
                skipASCII(2)
                selfClosing = true
                break
            }
            guard hadSpace else { throw malformed("Whitespace expected between attributes") }
            let (an, ap, al) = try qname()
            skipSpace()
            guard i < b.count, b[i] == 0x3D else { throw malformed("'=' expected after attribute '\(an)'") }
            skipASCII(1)
            skipSpace()
            let value = try attributeValue()
            for a in attrs where a.qualifiedName == an { throw malformed("'\(an)' is a duplicate attribute name") }
            let isDecl = an == "xmlns" || ap == "xmlns"
            attrs.append(XamlRawXMLAttribute(qualifiedName: an, prefix: ap, localName: al, namespaceURI: nil,
                                             value: value, isNamespaceDeclaration: isDecl))
        }
        // Namespace scope of this element.
        var scope: [String: String] = [:]
        var hasScope = false
        for a in attrs where a.isNamespaceDeclaration {
            hasScope = true
            if a.qualifiedName == "xmlns" { scope[""] = a.value } else {
                guard !a.value.isEmpty else { throw malformed("Cannot undeclare prefix '\(a.localName)'") }
                guard a.localName != "xmlns" else { throw malformed("The 'xmlns' prefix cannot be declared") }
                scope[a.localName] = a.value
            }
        }
        if hasScope { scopes.append(scope) }
        defer { if hasScope { scopes.removeLast() } }
        if prefix == "xmlns" { throw malformed("Element names cannot use the 'xmlns' prefix") }
        let ns = resolve(prefix)
        if let p = prefix, ns == nil { throw malformed("'\(p)' is an undeclared prefix") }
        var seen: Set<String>?
        for k in attrs.indices {
            if attrs[k].isNamespaceDeclaration {
                attrs[k].namespaceURI = XamlXMLNamespaces.xmlns
                continue
            }
            if let p = attrs[k].prefix {
                guard let uri = resolve(p) else { throw malformed("'\(p)' is an undeclared prefix") }
                attrs[k].namespaceURI = uri
                let key = uri + "|" + attrs[k].localName
                if seen == nil { seen = [] }
                if seen!.contains(key) { throw malformed("'\(attrs[k].qualifiedName)' is a duplicate attribute") }
                seen!.insert(key)
            }
        }
        let index = elements.count
        elements.append(XamlRawXMLElement(qualifiedName: qn, prefix: prefix, localName: local, namespaceURI: ns,
                                          attributes: attrs, children: [], range: start16..<p16,
                                          contentRange: p16..<p16, parent: parent))
        if selfClosing { return index }
        let content16 = p16
        var children: [XamlRawXMLChild] = []
        var text: [UInt8] = []
        var textStart16 = -1
        func flush(_ end16: Int, _ children: inout [XamlRawXMLChild], _ text: inout [UInt8], _ textStart16: inout Int) {
            if textStart16 >= 0 {
                children.append(.text(String(decoding: text, as: UTF8.self), textStart16..<end16, isCData: false))
                text.removeAll(keepingCapacity: true)
                textStart16 = -1
            }
        }
        while true {
            guard i < b.count else { throw malformed("Unexpected end of file; element '\(qn)' is not closed") }
            let c = b[i]
            if c == 0x3C {
                if i + 1 < b.count, b[i + 1] == 0x2F {
                    flush(p16, &children, &text, &textStart16)
                    let contentEnd16 = p16
                    skipASCII(2)
                    let (endName, _, _) = try qname()
                    skipSpace()
                    guard i < b.count, b[i] == 0x3E else { throw malformed("'>' expected in the end tag") }
                    skipASCII(1)
                    guard endName == qn else {
                        throw malformed("The '\(qn)' start tag does not match the end tag of '\(endName)'")
                    }
                    elements[index].children = children
                    elements[index].range = start16..<p16
                    elements[index].contentRange = content16..<contentEnd16
                    return index
                }
                if at("<!--") { flush(p16, &children, &text, &textStart16); try skipComment(); continue }
                if at("<![CDATA[") {
                    flush(p16, &children, &text, &textStart16)
                    let cs = p16
                    skipASCII(9)
                    var buf: [UInt8] = []
                    while true {
                        guard i + 2 < b.count else { throw malformed("Unexpected end of file in CDATA") }
                        if b[i] == 0x5D, b[i + 1] == 0x5D, b[i + 2] == 0x3E { skipASCII(3); break }
                        try appendLiteral(&buf)
                    }
                    children.append(.text(String(decoding: buf, as: UTF8.self), cs..<p16, isCData: true))
                    continue
                }
                if at("<?") { flush(p16, &children, &text, &textStart16); try skipPI(); continue }
                if at("<!") { throw malformed("Unexpected markup declaration inside an element") }
                flush(p16, &children, &text, &textStart16)
                let child = try element(parent: index, depth: depth + 1)
                children.append(.element(child))
                continue
            }
            if textStart16 < 0 { textStart16 = p16 }
            if c == 0x26 { try reference(&text); continue }
            // Fast path: a run of ordinary bytes.
            let runStart = i
            var w = 0
            while i < b.count {
                let d = b[i]
                if d == 0x3C || d == 0x26 || d == 0x0D || d == 0x5D || (d < 0x20 && d != 0x09 && d != 0x0A) || d == 0xEF {
                    break
                }
                w += Self.width16(d)
                i += 1
            }
            if i > runStart {
                text.append(contentsOf: b[runStart..<i])
                p16 += w
                continue
            }
            if c == 0x5D, i + 2 < b.count, b[i + 1] == 0x5D, b[i + 2] == 0x3E {
                throw malformed("']]>' is not allowed in content")
            }
            try appendLiteral(&text)
        }
    }

    /// Appends one literal character with XML end-of-line normalisation and character validation.
    @inline(__always) private mutating func appendLiteral(_ out: inout [UInt8]) throws {
        let c = b[i]
        if c == 0x0D {
            out.append(0x0A)
            skipASCII((i + 1 < b.count && b[i + 1] == 0x0A) ? 2 : 1)
            return
        }
        if c < 0x20, c != 0x09, c != 0x0A { throw malformed(String(format: "'\\u%04X' is an invalid character", Int(c))) }
        if c == 0xEF, i + 2 < b.count, b[i + 1] == 0xBF, b[i + 2] == 0xBE || b[i + 2] == 0xBF {
            throw malformed("'\\uFFFE' / '\\uFFFF' is an invalid character")
        }
        // One whole UTF-8 sequence.
        let n = c < 0x80 ? 1 : (c >= 0xF0 ? 4 : (c >= 0xE0 ? 3 : 2))
        out.append(contentsOf: b[i..<min(b.count, i + n)])
        p16 += n == 4 ? 2 : 1
        i += n
    }

    /// `&…;` at `i` → decoded into `out`.
    private mutating func reference(_ out: inout [UInt8]) throws {
        let start = i
        skipASCII(1)
        guard i < b.count else { throw malformed("Unexpected end of file in an entity reference") }
        if b[i] == 0x23 {
            skipASCII(1)
            var hex = false
            if i < b.count, b[i] == 0x78 { hex = true; skipASCII(1) }
            var v: UInt32 = 0
            var digits = 0
            while i < b.count, b[i] != 0x3B {
                let d = b[i]
                let dv: UInt32
                if d >= 0x30 && d <= 0x39 { dv = UInt32(d - 0x30) }
                else if hex && d >= 0x61 && d <= 0x66 { dv = UInt32(d - 0x61 + 10) }
                else if hex && d >= 0x41 && d <= 0x46 { dv = UInt32(d - 0x41 + 10) }
                else { throw malformed("Invalid character reference") }
                v = v &* (hex ? 16 : 10) &+ dv
                digits += 1
                if v > 0x10FFFF { throw malformed("Invalid character reference") }
                skipASCII(1)
            }
            guard digits > 0, i < b.count else { throw malformed("Invalid character reference") }
            skipASCII(1)
            guard let sc = Unicode.Scalar(v),
                  v == 0x9 || v == 0xA || v == 0xD || (v >= 0x20 && v <= 0xD7FF) || (v >= 0xE000 && v <= 0xFFFD)
                    || (v >= 0x10000 && v <= 0x10FFFF) else {
                i = start
                throw malformed("Character reference to an invalid character")
            }
            out.append(contentsOf: Array(String(Character(sc)).utf8))
            return
        }
        let ns = i
        while i < b.count, Self.isNameChar(b[i]), b[i] < 0x80 { skipASCII(1) }
        guard i < b.count, b[i] == 0x3B, i > ns else {
            i = start
            throw malformed("';' expected after an entity reference")
        }
        let n = String(decoding: b[ns..<i], as: UTF8.self)
        skipASCII(1)
        switch n {
        case "lt": out.append(0x3C)
        case "gt": out.append(0x3E)
        case "amp": out.append(0x26)
        case "apos": out.append(0x27)
        case "quot": out.append(0x22)
        default:
            i = start
            throw malformed("Reference to undeclared entity '\(n)'")
        }
    }

    private mutating func attributeValue() throws -> String {
        guard i < b.count, b[i] == 0x22 || b[i] == 0x27 else { throw malformed("Quote expected for an attribute value") }
        let q = b[i]
        skipASCII(1)
        var out: [UInt8] = []
        while true {
            guard i < b.count else { throw malformed("Unexpected end of file in an attribute value") }
            let c = b[i]
            if c == q { skipASCII(1); break }
            if c == 0x3C { throw malformed("'<' is not allowed in an attribute value") }
            if c == 0x26 { try reference(&out); continue }
            if c == 0x0D {                                              // CR LF / CR → one space
                out.append(0x20)
                skipASCII((i + 1 < b.count && b[i + 1] == 0x0A) ? 2 : 1)
                continue
            }
            if c == 0x0A || c == 0x09 { out.append(0x20); skipASCII(1); continue }
            try appendLiteral(&out)
        }
        return String(decoding: out, as: UTF8.self)
    }
}
