// Spec: 05 §XD.2.1 steps 1–4 (parse pipeline: BOM, declaration, DTD, namespaces, malformed XML), §XD.5 (hand-written
//       XML 1.0 tokenizer with UTF-16 source ranges, five predefined entities plus character references, undefined
//       entities rejected, end-of-line and attribute-value normalisation), §4.3.1 (reading tolerance).
// Phase 1 of `XamlDOM.parse`: a strict, namespace-aware XML reader that produces a raw element tree whose every
// element knows its exact UTF-16 range in the source (needed for byte-for-byte opaque preservation, §4.3.7 rule 10).
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
    /// Whole element: from `<` of the start tag to the end of the end tag (or of the empty-element tag).
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

/// Strict XML 1.0 (with namespaces) scanner over UTF-16 code units.
struct XamlXMLScanner {
    private let u: [UInt16]
    private var i: Int = 0
    private var elements: [XamlRawXMLElement] = []
    /// Namespace scopes: prefix ("" = default) → URI, innermost last.
    private var scopes: [[String: String]] = []
    private var depthLimit = 2_000

    init(units: [UInt16]) { self.u = units }

    struct Failure: Error { let fatal: XamlFatalError }

    static func scan(_ units: [UInt16]) -> Result<XamlRawXMLTree, XamlFatalError> {
        var s = XamlXMLScanner(units: units)
        do { return .success(try s.document()) } catch let f as Failure { return .failure(f.fatal) } catch {
            return .failure(.malformedXML("\(error)"))
        }
    }

    // MARK: - Errors

    private func malformed(_ what: String) -> Failure {
        let (line, col) = position(of: i)
        return Failure(fatal: .malformedXML("\(what) (line \(line), position \(col))"))
    }

    private func position(of index: Int) -> (Int, Int) {
        var line = 1, col = 1, k = 0
        let end = min(index, u.count)
        while k < end {
            if u[k] == 0x0A { line += 1; col = 1 } else { col += 1 }
            k += 1
        }
        return (line, col)
    }

    // MARK: - Character classes

    @inline(__always) private static func isSpace(_ c: UInt16) -> Bool { c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D }

    @inline(__always) private static func isNameStart(_ c: UInt16) -> Bool {
        (c >= 0x61 && c <= 0x7A) || (c >= 0x41 && c <= 0x5A) || c == 0x5F || c == 0x3A
            || (c >= 0xC0 && c != 0xD7 && c != 0xF7 && !(c >= 0x2000 && c <= 0x206F && c != 0x200C && c != 0x200D)
                && !(c >= 0xD800 && c <= 0xDFFF) && c != 0xFFFE && c != 0xFFFF) || (c >= 0xD800 && c <= 0xDBFF)
    }

    @inline(__always) private static func isNameChar(_ c: UInt16) -> Bool {
        isNameStart(c) || (c >= 0x30 && c <= 0x39) || c == 0x2D || c == 0x2E || c == 0xB7
            || (c >= 0x0300 && c <= 0x036F) || c == 0x203F || c == 0x2040 || (c >= 0xDC00 && c <= 0xDFFF)
    }

    /// XML 1.0 `Char` production for one UTF-16 unit; surrogates are validated as pairs by the caller.
    @inline(__always) private static func isXMLChar(_ c: UInt16) -> Bool {
        c == 0x09 || c == 0x0A || c == 0x0D || (c >= 0x20 && c <= 0xD7FF) || (c >= 0xE000 && c <= 0xFFFD)
            || (c >= 0xD800 && c <= 0xDFFF)
    }

    private func at(_ s: String) -> Bool {
        var k = i
        for c in s.utf16 {
            guard k < u.count, u[k] == c else { return false }
            k += 1
        }
        return true
    }

    private mutating func skipSpace() { while i < u.count, Self.isSpace(u[i]) { i += 1 } }

    // MARK: - Document

    private mutating func document() throws -> XamlRawXMLTree {
        if i < u.count, u[i] == 0xFEFF { i += 1 }                                     // XD.2.1 step 1
        skipSpace()
        if at("<?xml"), i + 5 < u.count, Self.isSpace(u[i + 5]) || u[i + 5] == 0x3F {
            try skipPI()
        }
        var root: Int?
        while true {
            skipSpace()
            if i >= u.count { break }
            guard u[i] == 0x3C else {
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
        i += 4
        while i + 2 < u.count {
            if u[i] == 0x2D, u[i + 1] == 0x2D {
                guard u[i + 2] == 0x3E else { throw malformed("'--' is not allowed inside a comment") }
                i += 3
                return
            }
            guard Self.isXMLChar(u[i]) else { throw malformed("Invalid character in a comment") }
            i += 1
        }
        throw malformed("Unexpected end of file in a comment")
    }

    private mutating func skipPI() throws {
        i += 2
        while i + 1 < u.count {
            if u[i] == 0x3F, u[i + 1] == 0x3E { i += 2; return }
            i += 1
        }
        throw malformed("Unexpected end of file in a processing instruction")
    }

    // MARK: - Names

    private mutating func name() throws -> String {
        let start = i
        guard i < u.count, Self.isNameStart(u[i]) else { throw malformed("Name expected") }
        i += 1
        while i < u.count, Self.isNameChar(u[i]) { i += 1 }
        return String(decoding: u[start..<i], as: UTF16.self)
    }

    private func split(_ qname: String) throws -> (String?, String) {
        guard let colon = qname.firstIndex(of: ":") else { return (nil, qname) }
        let p = String(qname[..<colon]), l = String(qname[qname.index(after: colon)...])
        guard !p.isEmpty, !l.isEmpty, !l.contains(":") else { throw malformed("Invalid qualified name '\(qname)'") }
        return (p, l)
    }

    private func resolve(_ prefix: String?) -> String? {
        let key = prefix ?? ""
        for scope in scopes.reversed() { if let v = scope[key] { return v.isEmpty ? nil : v } }
        return nil
    }

    // MARK: - Elements

    private mutating func element(parent: Int?, depth: Int) throws -> Int {
        guard depth < depthLimit else { throw malformed("The document is nested too deeply") }
        let start = i
        i += 1                                                          // '<'
        let qname = try name()
        var attrs: [XamlRawXMLAttribute] = []
        var selfClosing = false
        while true {
            let hadSpace = i < u.count && Self.isSpace(u[i])
            skipSpace()
            guard i < u.count else { throw malformed("Unexpected end of file in a start tag") }
            if u[i] == 0x3E { i += 1; break }
            if u[i] == 0x2F {
                guard i + 1 < u.count, u[i + 1] == 0x3E else { throw malformed("'/' must be followed by '>'") }
                i += 2
                selfClosing = true
                break
            }
            guard hadSpace else { throw malformed("Whitespace expected between attributes") }
            let an = try name()
            skipSpace()
            guard i < u.count, u[i] == 0x3D else { throw malformed("'=' expected after attribute '\(an)'") }
            i += 1
            skipSpace()
            let value = try attributeValue()
            if attrs.contains(where: { $0.qualifiedName == an }) {
                throw malformed("'\(an)' is a duplicate attribute name")
            }
            let (ap, al) = try split(an)
            let isDecl = an == "xmlns" || ap == "xmlns"
            attrs.append(XamlRawXMLAttribute(qualifiedName: an, prefix: ap, localName: al, namespaceURI: nil,
                                             value: value, isNamespaceDeclaration: isDecl))
        }
        // Namespace scope of this element.
        var scope: [String: String] = [:]
        for a in attrs where a.isNamespaceDeclaration {
            if a.qualifiedName == "xmlns" { scope[""] = a.value } else {
                guard !a.value.isEmpty else { throw malformed("Cannot undeclare prefix '\(a.localName)'") }
                guard a.localName != "xmlns" else { throw malformed("The 'xmlns' prefix cannot be declared") }
                scope[a.localName] = a.value
            }
        }
        scopes.append(scope)
        defer { scopes.removeLast() }
        let (prefix, local) = try split(qname)
        if prefix == "xmlns" { throw malformed("Element names cannot use the 'xmlns' prefix") }
        let ns = resolve(prefix)
        if prefix != nil, ns == nil { throw malformed("'\(prefix!)' is an undeclared prefix") }
        var seen = Set<String>()
        for k in attrs.indices {
            if attrs[k].isNamespaceDeclaration {
                attrs[k].namespaceURI = XamlXMLNamespaces.xmlns
                continue
            }
            if let p = attrs[k].prefix {
                guard let uri = resolve(p) else { throw malformed("'\(p)' is an undeclared prefix") }
                attrs[k].namespaceURI = uri
                let key = uri + "|" + attrs[k].localName
                if seen.contains(key) { throw malformed("'\(attrs[k].qualifiedName)' is a duplicate attribute") }
                seen.insert(key)
            }
        }
        let index = elements.count
        elements.append(XamlRawXMLElement(qualifiedName: qname, prefix: prefix, localName: local, namespaceURI: ns,
                                          attributes: attrs, children: [], range: start..<i, contentRange: i..<i,
                                          parent: parent))
        if selfClosing { return index }
        let contentStart = i
        var children: [XamlRawXMLChild] = []
        var textStart = -1
        var text: [UInt16] = []
        func flushText(_ end: Int, into children: inout [XamlRawXMLChild]) {
            if textStart >= 0 {
                children.append(.text(String(decoding: text, as: UTF16.self), textStart..<end, isCData: false))
                text.removeAll(keepingCapacity: true)
                textStart = -1
            }
        }
        while true {
            guard i < u.count else { throw malformed("Unexpected end of file; element '\(qname)' is not closed") }
            let c = u[i]
            if c == 0x3C {
                if i + 1 < u.count, u[i + 1] == 0x2F {
                    flushText(i, into: &children)
                    let contentEnd = i
                    i += 2
                    let endName = try name()
                    skipSpace()
                    guard i < u.count, u[i] == 0x3E else { throw malformed("'>' expected in the end tag") }
                    i += 1
                    guard endName == qname else {
                        throw malformed("The '\(qname)' start tag does not match the end tag of '\(endName)'")
                    }
                    elements[index].children = children
                    elements[index].range = start..<i
                    elements[index].contentRange = contentStart..<contentEnd
                    return index
                }
                if at("<!--") { flushText(i, into: &children); try skipComment(); continue }
                if at("<![CDATA[") {
                    flushText(i, into: &children)
                    let cs = i
                    i += 9
                    var buf: [UInt16] = []
                    while true {
                        guard i + 2 < u.count else { throw malformed("Unexpected end of file in CDATA") }
                        if u[i] == 0x5D, u[i + 1] == 0x5D, u[i + 2] == 0x3E { i += 3; break }
                        try appendLiteral(&buf)
                    }
                    children.append(.text(String(decoding: buf, as: UTF16.self), cs..<i, isCData: true))
                    continue
                }
                if at("<?") { flushText(i, into: &children); try skipPI(); continue }
                if at("<!") { throw malformed("Unexpected markup declaration inside an element") }
                flushText(i, into: &children)
                let child = try element(parent: index, depth: depth + 1)
                children.append(.element(child))
                continue
            }
            if textStart < 0 { textStart = i }
            if c == 0x26 {
                try reference(&text)
                continue
            }
            if c == 0x5D, i + 2 < u.count, u[i + 1] == 0x5D, u[i + 2] == 0x3E {
                throw malformed("']]>' is not allowed in content")
            }
            try appendLiteral(&text)
        }
    }

    /// Appends one literal character (or surrogate pair) with XML end-of-line normalisation.
    @inline(__always) private mutating func appendLiteral(_ out: inout [UInt16]) throws {
        let c = u[i]
        if c == 0x0D {
            out.append(0x0A)
            i += (i + 1 < u.count && u[i + 1] == 0x0A) ? 2 : 1
            return
        }
        if c >= 0xD800 && c <= 0xDBFF {
            guard i + 1 < u.count, u[i + 1] >= 0xDC00, u[i + 1] <= 0xDFFF else { throw malformed("Invalid surrogate") }
            out.append(c); out.append(u[i + 1])
            i += 2
            return
        }
        guard Self.isXMLChar(c), !(c >= 0xDC00 && c <= 0xDFFF) else {
            throw malformed(String(format: "'\\u%04X' is an invalid character", Int(c)))
        }
        out.append(c)
        i += 1
    }

    /// `&…;` at `i` → decoded into `out`.
    private mutating func reference(_ out: inout [UInt16]) throws {
        let start = i
        i += 1
        guard i < u.count else { throw malformed("Unexpected end of file in an entity reference") }
        if u[i] == 0x23 {
            i += 1
            var hex = false
            if i < u.count, u[i] == 0x78 { hex = true; i += 1 }
            var v: UInt32 = 0
            var digits = 0
            while i < u.count, u[i] != 0x3B {
                let d = u[i]
                let dv: UInt32
                if d >= 0x30 && d <= 0x39 { dv = UInt32(d - 0x30) }
                else if hex && d >= 0x61 && d <= 0x66 { dv = UInt32(d - 0x61 + 10) }
                else if hex && d >= 0x41 && d <= 0x46 { dv = UInt32(d - 0x41 + 10) }
                else { throw malformed("Invalid character reference") }
                v = v &* (hex ? 16 : 10) &+ dv
                digits += 1
                if v > 0x10FFFF { throw malformed("Invalid character reference") }
                i += 1
            }
            guard digits > 0, i < u.count else { throw malformed("Invalid character reference") }
            i += 1
            guard let sc = Unicode.Scalar(v),
                  v == 0x9 || v == 0xA || v == 0xD || (v >= 0x20 && v <= 0xD7FF) || (v >= 0xE000 && v <= 0xFFFD)
                    || (v >= 0x10000 && v <= 0x10FFFF) else {
                i = start
                throw malformed("Character reference to an invalid character")
            }
            out.append(contentsOf: String(Character(sc)).utf16)
            return
        }
        let n = try name()
        guard i < u.count, u[i] == 0x3B else { throw malformed("';' expected after an entity reference") }
        i += 1
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
        guard i < u.count, u[i] == 0x22 || u[i] == 0x27 else { throw malformed("Quote expected for an attribute value") }
        let q = u[i]
        i += 1
        var out: [UInt16] = []
        while true {
            guard i < u.count else { throw malformed("Unexpected end of file in an attribute value") }
            let c = u[i]
            if c == q { i += 1; break }
            if c == 0x3C { throw malformed("'<' is not allowed in an attribute value") }
            if c == 0x26 { try reference(&out); continue }
            if c == 0x0D {                                              // CR LF / CR → one space
                out.append(0x20)
                i += (i + 1 < u.count && u[i + 1] == 0x0A) ? 2 : 1
                continue
            }
            if c == 0x0A || c == 0x09 { out.append(0x20); i += 1; continue }
            try appendLiteral(&out)
        }
        return String(decoding: out, as: UTF16.self)
    }
}
