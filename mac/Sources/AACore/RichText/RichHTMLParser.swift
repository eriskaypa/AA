// Spec: 05 §3.3 step 1 (HtmlAgilityPack load: auto-close on end, fix nested tags, element names lower-cased,
//       comments ignored, script/style raw text), step 4 (`HtmlEntity.DeEntitize`: the HTML 4 named entities and
//       `&#N;` / `&#xH;`; unknown names stay as written). A small, tolerant HTML reader that builds the same tree shape
//       the converter walks on Windows; no Apple HTML importer (WebKit/Tidy) is involved, so paste results match.
import Foundation

final class RichHTMLNode {
    enum Kind { case document, element, text, comment }
    let kind: Kind
    /// Lower-cased element name; `#document`, `#text`, `#comment` otherwise.
    let name: String
    /// Attribute names lower-cased, values entity-decoded, in source order.
    var attributes: [(String, String)] = []
    /// Raw text of a text node (entities not decoded; `DeEntitize` is applied by the converter).
    var text: String = ""
    var children: [RichHTMLNode] = []
    weak var parent: RichHTMLNode?

    init(kind: Kind, name: String) { self.kind = kind; self.name = name }

    func attribute(_ name: String) -> String? { attributes.first { $0.0 == name }?.1 }

    /// HtmlAgilityPack `GetAttributeValue(name, int def)`: `Convert.ToInt32` semantics, the default on any failure.
    func intAttribute(_ name: String, default def: Int) -> Int {
        guard let v = attribute(name), let n = XamlValues.parseInt(v) else { return def }
        return n
    }

    var descendants: [RichHTMLNode] {
        var out: [RichHTMLNode] = []
        for c in children { out.append(c); out.append(contentsOf: c.descendants) }
        return out
    }

    func remove() {
        guard let p = parent else { return }
        p.children.removeAll { $0 === self }
        parent = nil
    }
}

enum RichHTMLParser {
    static let voidElements: Set<String> = ["area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta",
                                            "param", "source", "track", "wbr", "basefont", "frame", "isindex", "keygen",
                                            "bgsound", "spacer"]
    static let rawTextElements: Set<String> = ["script", "style", "textarea", "title", "xmp", "noxhtml"]

    static func parse(_ html: String) -> RichHTMLNode {
        let u = Array(html.utf16)
        let doc = RichHTMLNode(kind: .document, name: "#document")
        var stack: [RichHTMLNode] = [doc]
        var i = 0
        var textStart = -1

        func current() -> RichHTMLNode { stack.last! }
        func append(_ n: RichHTMLNode) { n.parent = current(); current().children.append(n) }
        func flushText(_ end: Int) {
            guard textStart >= 0, end > textStart else { textStart = -1; return }
            let t = String(decoding: u[textStart..<end], as: UTF16.self)
            if let last = current().children.last, last.kind == .text { last.text += t } else {
                let n = RichHTMLNode(kind: .text, name: "#text")
                n.text = t
                append(n)
            }
            textStart = -1
        }
        func isLetter(_ c: UInt16) -> Bool { (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A) }
        func isSpace(_ c: UInt16) -> Bool { c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D || c == 0x0C }
        func lower(_ s: String) -> String { s.lowercased() }
        func find(_ needle: String, from k: Int, caseInsensitive: Bool) -> Int? {
            let n = Array((caseInsensitive ? needle.lowercased() : needle).utf16)
            guard !n.isEmpty, k <= u.count - n.count else { return nil }
            var p = k
            while p <= u.count - n.count {
                var ok = true
                for q in 0..<n.count {
                    var c = u[p + q]
                    if caseInsensitive, c >= 0x41, c <= 0x5A { c += 0x20 }
                    if c != n[q] { ok = false; break }
                }
                if ok { return p }
                p += 1
            }
            return nil
        }
        /// OptionFixNestedTags: a new li / tr / td / th closes the open one of the same kind within its container.
        func fixNested(_ name: String) {
            let (targets, resetters): (Set<String>, Set<String>)
            switch name {
            case "li": (targets, resetters) = (["li"], ["ul", "ol", "menu", "dir"])
            case "tr": (targets, resetters) = (["tr"], ["table", "thead", "tbody", "tfoot"])
            case "td", "th": (targets, resetters) = (["td", "th"], ["tr", "table"])
            case "option": (targets, resetters) = (["option"], ["select", "datalist", "optgroup"])
            default: return
            }
            var k = stack.count - 1
            while k > 0 {
                let n = stack[k].name
                if resetters.contains(n) { return }
                if targets.contains(n) { stack.removeSubrange(k...); return }
                k -= 1
            }
        }

        while i < u.count {
            let c = u[i]
            guard c == 0x3C else {
                if textStart < 0 { textStart = i }
                i += 1
                continue
            }
            // Comment.
            if i + 3 < u.count, u[i + 1] == 0x21, u[i + 2] == 0x2D, u[i + 3] == 0x2D {
                flushText(i)
                let end = find("-->", from: i + 4, caseInsensitive: false)
                i = end.map { $0 + 3 } ?? u.count
                continue
            }
            // Declarations / processing instructions.
            if i + 1 < u.count, u[i + 1] == 0x21 || u[i + 1] == 0x3F {
                flushText(i)
                var k = i + 2
                while k < u.count, u[k] != 0x3E { k += 1 }
                i = min(u.count, k + 1)
                continue
            }
            // End tag.
            if i + 2 < u.count, u[i + 1] == 0x2F, isLetter(u[i + 2]) {
                flushText(i)
                var k = i + 2
                while k < u.count, !isSpace(u[k]), u[k] != 0x3E, u[k] != 0x2F { k += 1 }
                let name = lower(String(decoding: u[(i + 2)..<k], as: UTF16.self))
                while k < u.count, u[k] != 0x3E { k += 1 }
                i = min(u.count, k + 1)
                if let idx = stack.lastIndex(where: { $0.name == name }), idx > 0 { stack.removeSubrange(idx...) }
                continue
            }
            // Start tag.
            guard i + 1 < u.count, isLetter(u[i + 1]) else {
                if textStart < 0 { textStart = i }
                i += 1
                continue
            }
            flushText(i)
            var k = i + 1
            while k < u.count, !isSpace(u[k]), u[k] != 0x3E, u[k] != 0x2F { k += 1 }
            let name = lower(String(decoding: u[(i + 1)..<k], as: UTF16.self))
            let el = RichHTMLNode(kind: .element, name: name)
            var selfClosing = false
            // Attributes.
            while k < u.count {
                while k < u.count, isSpace(u[k]) { k += 1 }
                guard k < u.count else { break }
                if u[k] == 0x3E { k += 1; break }
                if u[k] == 0x2F {
                    if k + 1 < u.count, u[k + 1] == 0x3E { selfClosing = true; k += 2; break }
                    k += 1
                    continue
                }
                let ns = k
                while k < u.count, !isSpace(u[k]), u[k] != 0x3D, u[k] != 0x3E, !(u[k] == 0x2F && k + 1 < u.count && u[k + 1] == 0x3E) {
                    k += 1
                }
                let an = lower(String(decoding: u[ns..<k], as: UTF16.self))
                while k < u.count, isSpace(u[k]) { k += 1 }
                var value = ""
                if k < u.count, u[k] == 0x3D {
                    k += 1
                    while k < u.count, isSpace(u[k]) { k += 1 }
                    if k < u.count, u[k] == 0x22 || u[k] == 0x27 {
                        let q = u[k]
                        k += 1
                        let vs = k
                        while k < u.count, u[k] != q { k += 1 }
                        value = String(decoding: u[vs..<min(k, u.count)], as: UTF16.self)
                        if k < u.count { k += 1 }
                    } else {
                        let vs = k
                        while k < u.count, !isSpace(u[k]), u[k] != 0x3E { k += 1 }
                        value = String(decoding: u[vs..<k], as: UTF16.self)
                    }
                }
                if !an.isEmpty, !el.attributes.contains(where: { $0.0 == an }) {
                    el.attributes.append((an, RichHTMLEntities.decode(value)))
                }
            }
            i = k
            fixNested(name)
            append(el)
            if rawTextElements.contains(name) && !selfClosing {
                let end = find("</" + name, from: i, caseInsensitive: true) ?? u.count
                if end > i {
                    let t = RichHTMLNode(kind: .text, name: "#text")
                    t.text = String(decoding: u[i..<end], as: UTF16.self)
                    t.parent = el
                    el.children.append(t)
                }
                var e = end
                while e < u.count, u[e] != 0x3E { e += 1 }
                i = min(u.count, e + 1)
                continue
            }
            if !selfClosing && !voidElements.contains(name) { stack.append(el) }
        }
        flushText(u.count)
        return doc
    }
}

/// `HtmlEntity.DeEntitize`: the HTML 4 entity set (+ `apos`) and numeric references; unknown names stay verbatim.
enum RichHTMLEntities {
    static func decode(_ s: String) -> String {
        guard s.contains("&") else { return s }
        var out = String.UnicodeScalarView()
        let scalars = Array(s.unicodeScalars)
        var i = 0
        while i < scalars.count {
            let c = scalars[i]
            guard c == "&", let semi = scalars[(i + 1)...].prefix(33).firstIndex(of: ";"), semi > i + 1 else {
                out.append(c); i += 1; continue
            }
            let body = String(String.UnicodeScalarView(scalars[(i + 1)..<semi]))
            var decoded: Unicode.Scalar?
            if body.hasPrefix("#") {
                let digits = body.dropFirst()
                let v: UInt32?
                if digits.hasPrefix("x") || digits.hasPrefix("X") { v = UInt32(digits.dropFirst(), radix: 16) }
                else { v = UInt32(digits, radix: 10) }
                if let v, v > 0 { decoded = Unicode.Scalar(v) }
            } else if let v = table[body] {
                decoded = Unicode.Scalar(v)
            }
            if let d = decoded {
                out.append(d)
                i = semi + 1
            } else {
                out.append(c); i += 1
            }
        }
        return String(out)
    }

    static let table: [String: UInt32] = {
        var t: [String: UInt32] = ["quot": 34, "amp": 38, "apos": 39, "lt": 60, "gt": 62]
        let latin1 = ["nbsp", "iexcl", "cent", "pound", "curren", "yen", "brvbar", "sect", "uml", "copy", "ordf", "laquo",
                      "not", "shy", "reg", "macr", "deg", "plusmn", "sup2", "sup3", "acute", "micro", "para", "middot",
                      "cedil", "sup1", "ordm", "raquo", "frac14", "frac12", "frac34", "iquest", "Agrave", "Aacute",
                      "Acirc", "Atilde", "Auml", "Aring", "AElig", "Ccedil", "Egrave", "Eacute", "Ecirc", "Euml",
                      "Igrave", "Iacute", "Icirc", "Iuml", "ETH", "Ntilde", "Ograve", "Oacute", "Ocirc", "Otilde",
                      "Ouml", "times", "Oslash", "Ugrave", "Uacute", "Ucirc", "Uuml", "Yacute", "THORN", "szlig",
                      "agrave", "aacute", "acirc", "atilde", "auml", "aring", "aelig", "ccedil", "egrave", "eacute",
                      "ecirc", "euml", "igrave", "iacute", "icirc", "iuml", "eth", "ntilde", "ograve", "oacute",
                      "ocirc", "otilde", "ouml", "divide", "oslash", "ugrave", "uacute", "ucirc", "uuml", "yacute",
                      "thorn", "yuml"]
        for (k, n) in latin1.enumerated() { t[n] = UInt32(160 + k) }
        let rest: [(String, UInt32)] = [
            ("OElig", 338), ("oelig", 339), ("Scaron", 352), ("scaron", 353), ("Yuml", 376), ("fnof", 402),
            ("circ", 710), ("tilde", 732), ("Alpha", 913), ("Beta", 914), ("Gamma", 915), ("Delta", 916),
            ("Epsilon", 917), ("Zeta", 918), ("Eta", 919), ("Theta", 920), ("Iota", 921), ("Kappa", 922),
            ("Lambda", 923), ("Mu", 924), ("Nu", 925), ("Xi", 926), ("Omicron", 927), ("Pi", 928), ("Rho", 929),
            ("Sigma", 931), ("Tau", 932), ("Upsilon", 933), ("Phi", 934), ("Chi", 935), ("Psi", 936), ("Omega", 937),
            ("alpha", 945), ("beta", 946), ("gamma", 947), ("delta", 948), ("epsilon", 949), ("zeta", 950),
            ("eta", 951), ("theta", 952), ("iota", 953), ("kappa", 954), ("lambda", 955), ("mu", 956), ("nu", 957),
            ("xi", 958), ("omicron", 959), ("pi", 960), ("rho", 961), ("sigmaf", 962), ("sigma", 963), ("tau", 964),
            ("upsilon", 965), ("phi", 966), ("chi", 967), ("psi", 968), ("omega", 969), ("thetasym", 977),
            ("upsih", 978), ("piv", 982), ("ensp", 8194), ("emsp", 8195), ("thinsp", 8201), ("zwnj", 8204),
            ("zwj", 8205), ("lrm", 8206), ("rlm", 8207), ("ndash", 8211), ("mdash", 8212), ("lsquo", 8216),
            ("rsquo", 8217), ("sbquo", 8218), ("ldquo", 8220), ("rdquo", 8221), ("bdquo", 8222), ("dagger", 8224),
            ("Dagger", 8225), ("bull", 8226), ("hellip", 8230), ("permil", 8240), ("prime", 8242), ("Prime", 8243),
            ("lsaquo", 8249), ("rsaquo", 8250), ("oline", 8254), ("frasl", 8260), ("euro", 8364), ("image", 8465),
            ("weierp", 8472), ("real", 8476), ("trade", 8482), ("alefsym", 8501), ("larr", 8592), ("uarr", 8593),
            ("rarr", 8594), ("darr", 8595), ("harr", 8596), ("crarr", 8629), ("lArr", 8656), ("uArr", 8657),
            ("rArr", 8658), ("dArr", 8659), ("hArr", 8660), ("forall", 8704), ("part", 8706), ("exist", 8707),
            ("empty", 8709), ("nabla", 8711), ("isin", 8712), ("notin", 8713), ("ni", 8715), ("prod", 8719),
            ("sum", 8721), ("minus", 8722), ("lowast", 8727), ("radic", 8730), ("prop", 8733), ("infin", 8734),
            ("ang", 8736), ("and", 8743), ("or", 8744), ("cap", 8745), ("cup", 8746), ("int", 8747),
            ("there4", 8756), ("sim", 8764), ("cong", 8773), ("asymp", 8776), ("ne", 8800), ("equiv", 8801),
            ("le", 8804), ("ge", 8805), ("sub", 8834), ("sup", 8835), ("nsub", 8836), ("sube", 8838),
            ("supe", 8839), ("oplus", 8853), ("otimes", 8855), ("perp", 8869), ("sdot", 8901), ("lceil", 8968),
            ("rceil", 8969), ("lfloor", 8970), ("rfloor", 8971), ("lang", 9001), ("rang", 9002), ("loz", 9674),
            ("spades", 9824), ("clubs", 9827), ("hearts", 9829), ("diams", 9830),
        ]
        for (n, v) in rest { t[n] = v }
        return t
    }()
}
