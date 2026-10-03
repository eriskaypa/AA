// `xml-canonical` comparison (spec 01 GF.4.9, GF.6.9, GF.9): parse with namespaces on, sort attributes by
// (namespace, local name), keep text nodes byte-exact (the XAML uses xml:space="preserve", so whitespace is
// significant), normalise empty elements to `<X />` and entities to `&amp; &lt; &gt; &quot;`, then compare.
// Comments and processing instructions carry no content in the XAML vocabulary and are dropped.
import Foundation

enum GoldXMLCanonicalizer {
    struct Failure: Error, CustomStringConvertible {
        var message: String
        var line: Int
        var description: String { "XML parse error at line \(line): \(message)" }
    }

    /// The canonical text of `xml`.
    static func canonicalize(_ xml: String) throws -> String {
        try canonicalize(Data(xml.utf8))
    }

    static func canonicalize(_ data: Data) throws -> String {
        let builder = Builder()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.shouldReportNamespacePrefixes = true
        parser.shouldResolveExternalEntities = false
        parser.delegate = builder
        if !parser.parse() {
            throw Failure(message: parser.parserError.map { String(describing: $0) } ?? "unknown", line: parser.lineNumber)
        }
        return builder.output
    }

    /// True when both documents have the same canonical form.
    static func equivalent(_ a: String, _ b: String) throws -> Bool {
        try canonicalize(a) == canonicalize(b)
    }

    /// The first difference between the canonical forms, or nil.
    static func difference(golden: Data, actual: Data) -> GoldMismatch? {
        let g: String, a: String
        do { g = try canonicalize(golden) } catch { return GoldMismatch(reason: "golden: \(error)") }
        do { a = try canonicalize(actual) } catch { return GoldMismatch(reason: "actual: \(error)") }
        if g == a { return nil }
        let gb = Array(g.utf8), ab = Array(a.utf8)
        let off = GoldenMatcher.firstDifference(gb, ab) ?? 0
        return GoldMismatch(reason: "canonical XML differs", offset: off,
                            expectedContext: GoldenMatcher.contextAround(gb, off),
                            actualContext: GoldenMatcher.contextAround(ab, off))
    }

    static func escapeText(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.utf8.count)
        for c in s.unicodeScalars {
            switch c {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            default: out.unicodeScalars.append(c)
            }
        }
        return out
    }

    static func escapeAttribute(_ s: String) -> String {
        escapeText(s).replacingOccurrences(of: "\"", with: "&quot;")
    }

    // MARK: SAX → canonical text

    private final class Builder: NSObject, XMLParserDelegate {
        struct Open {
            var name: String
            var hasContent = false
        }

        var output = ""
        private var stack: [Open] = []
        private var pendingNamespaces: [(prefix: String, uri: String)] = []
        private var text = ""
        /// Start tag written but not yet closed with ">" (so an empty element can become `<X />`).
        private var startTagOpen = false

        func parser(_ parser: XMLParser, didStartMappingPrefix prefix: String, toURI namespaceURI: String) {
            pendingNamespaces.append((prefix, namespaceURI))
        }

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                    qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
            flushText()
            closeStartTag()
            if !stack.isEmpty { stack[stack.count - 1].hasContent = true }
            let name = qName ?? elementName
            output += "<" + name
            // Namespace declarations first (sorted by prefix), then attributes sorted by (namespace, local name).
            for ns in pendingNamespaces.sorted(by: { $0.prefix < $1.prefix }) {
                output += ns.prefix.isEmpty ? " xmlns=\"" : " xmlns:\(ns.prefix)=\""
                output += GoldXMLCanonicalizer.escapeAttribute(ns.uri) + "\""
            }
            pendingNamespaces.removeAll()
            let sorted = attributeDict.map { (key: $0.key, value: $0.value) }.sorted { lhs, rhs in
                let l = Self.split(lhs.key), r = Self.split(rhs.key)
                return l.prefix != r.prefix ? l.prefix < r.prefix : l.local < r.local
            }
            for a in sorted { output += " \(a.key)=\"\(GoldXMLCanonicalizer.escapeAttribute(a.value))\"" }
            stack.append(Open(name: name))
            startTagOpen = true
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                    qualifiedName qName: String?) {
            flushText()
            let open = stack.removeLast()
            if startTagOpen && !open.hasContent {
                output += " />"
                startTagOpen = false
            } else {
                closeStartTag()
                output += "</\(open.name)>"
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }
        func parser(_ parser: XMLParser, foundIgnorableWhitespace whitespaceString: String) { text += whitespaceString }
        func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) { text += String(decoding: CDATABlock, as: UTF8.self) }

        private func flushText() {
            guard !text.isEmpty else { return }
            if stack.isEmpty { text = ""; return }          // whitespace around the root element is not content
            closeStartTag()
            stack[stack.count - 1].hasContent = true
            output += GoldXMLCanonicalizer.escapeText(text)
            text = ""
        }

        private func closeStartTag() {
            if startTagOpen { output += ">"; startTagOpen = false }
        }

        /// `x:Name` → ("x", "Name"); `Name` → ("", "Name"). The prefix stands in for the namespace: within one
        /// document a prefix maps to one namespace, and the XAML vocabulary never rebinds them.
        static func split(_ q: String) -> (prefix: String, local: String) {
            if let i = q.firstIndex(of: ":") { return (String(q[..<i]), String(q[q.index(after: i)...])) }
            return ("", q)
        }
    }
}
