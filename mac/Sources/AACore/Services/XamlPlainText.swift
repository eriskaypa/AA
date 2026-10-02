// Spec: 02 REPO-104, §3.2 (`PlainTextFromXaml`, XmlReader emulation with XMLParser text coalescing), §7.7; 08 §3.4,
//       T-SR-5…7, T-SR-11; DECISIONS 08 OQ-7 (search matches across formatting runs: adjacent inline runs of one
//       paragraph join without a space — recorded in Deviations/F2.md); 01 §3.15 / 08 §3.7 (`DataDiff.PlainText`:
//       regex strip + `WebUtility.HtmlDecode` + whitespace collapse + trim). Lives in Services (ARCH §1.2).
import Foundation

public enum XamlPlainText {
    /// REPO-104: `""` for empty input. Otherwise the XML is streamed: each text node (and each whitespace-only node
    /// inside an `xml:space="preserve"` scope) contributes its decoded text followed by one space, and the start of
    /// every `Paragraph`, `LineBreak` and `ListItem` element contributes one space; attributes, element names,
    /// comments, CDATA and insignificant whitespace contribute nothing. DECISIONS 08 OQ-7: text nodes separated only
    /// by inline element boundaries (`Run`, `Span`, `Bold`, `Italic`, `Underline`, `Hyperlink`) are joined without
    /// the separating space, so a word split across formatting runs is still found. Any XML error (a legacy `enc:`
    /// blob, a multi-root fragment, an undefined entity, a DTD) falls back to replacing every `<[^>]+>` with one
    /// space (entities not decoded).
    public static func searchText(_ xaml: String) -> String {
        guard !xaml.isEmpty else { return "" }
        if xaml.contains("<!DOCTYPE") { return regexStrip(xaml) }        // XmlReader: DtdProcessing.Prohibit
        let collector = SvcXamlTextCollector(joinRuns: true)
        let parser = XMLParser(data: Data(xaml.utf8))
        parser.delegate = collector
        parser.shouldProcessNamespaces = true
        parser.shouldResolveExternalEntities = false
        guard parser.parse(), !collector.failed else { return regexStrip(xaml) }
        return collector.finish()
    }

    /// 01 §3.15 `PlainText`: `""` for empty input; every `<[^>]+>` → one space; HTML entities decoded
    /// (`WebUtility.HtmlDecode`: the HTML 4 named entities and `&#NN;` / `&#xHH;`); every run of .NET `\s` → one
    /// space; trimmed. Formatting-only edits therefore never register as a notes change.
    public static func diffText(_ xaml: String) -> String {
        guard !xaml.isEmpty else { return "" }
        let decoded = SvcHtmlEntities.decode(regexStrip(xaml))
        var out: [UInt16] = []
        out.reserveCapacity(decoded.utf16.count)
        var inSpace = false
        for u in decoded.utf16 {
            if NetText.isWhiteSpace(u) {
                if !inSpace { out.append(0x20); inSpace = true }
            } else {
                out.append(u)
                inSpace = false
            }
        }
        return NetText.trim(String(decoding: out, as: UTF16.self))
    }

    /// Regex `<[^>]+>` → `" "` (a `<` with at least one character before the next `>`).
    static func regexStrip(_ s: String) -> String {
        let u = Array(s.utf16)
        var out: [UInt16] = []
        out.reserveCapacity(u.count)
        var i = 0
        while i < u.count {
            if u[i] == 0x3C, i + 1 < u.count, u[i + 1] != 0x3E, let close = u[(i + 1)...].firstIndex(of: 0x3E) {
                out.append(0x20)
                i = close + 1
            } else {
                out.append(u[i])
                i += 1
            }
        }
        return String(decoding: out, as: UTF16.self)
    }
}

/// SAX delegate reproducing `XmlReader` text-node semantics (02 §3.2 Swift note).
final class SvcXamlTextCollector: NSObject, XMLParserDelegate {
    private static let breakers: Set<String> = ["Paragraph", "LineBreak", "ListItem"]
    private static let inline: Set<String> = ["Run", "Span", "Bold", "Italic", "Underline", "Hyperlink"]

    private let joinRuns: Bool
    private var out = ""
    private var chunk = ""
    private var hasChunk = false
    private var preserve: [Bool] = [false]
    private var owedSpace = false
    private var joinable = false
    private(set) var failed = false

    init(joinRuns: Bool) { self.joinRuns = joinRuns }

    func finish() -> String {
        flush()
        if owedSpace { out += " "; owedSpace = false }
        return out
    }

    /// Ends the current text node.
    private func flush() {
        guard hasChunk else { return }
        let text = chunk
        chunk = ""
        hasChunk = false
        let whitespaceOnly = text.utf16.allSatisfy { $0 == 0x20 || $0 == 0x09 || $0 == 0x0A || $0 == 0x0D }
        if whitespaceOnly && !(preserve.last ?? false) {                  // XmlNodeType.Whitespace: ignored
            breakRun()
            return
        }
        if owedSpace && !(joinRuns && joinable) { out += " " }
        out += text
        owedSpace = true
        joinable = true
    }

    /// A boundary that is not an inline run boundary: the owed separator space is written.
    private func breakRun() {
        if owedSpace { out += " "; owedSpace = false }
        joinable = false
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        flush()
        let space = attributeDict["xml:space"] ?? attributeDict["space"]
        preserve.append(space.map { $0 == "preserve" } ?? (preserve.last ?? false))
        if !Self.inline.contains(elementName) { breakRun() }
        if Self.breakers.contains(elementName) { out += " " }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?) {
        flush()
        if preserve.count > 1 { preserve.removeLast() }
        if !Self.inline.contains(elementName) { breakRun() }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        chunk += string
        hasChunk = true
    }

    func parser(_ parser: XMLParser, foundIgnorableWhitespace whitespaceString: String) {
        chunk += whitespaceString
        hasChunk = true
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) { flush(); breakRun() }
    func parser(_ parser: XMLParser, foundComment comment: String) { flush(); breakRun() }
    func parser(_ parser: XMLParser, foundProcessingInstructionWithTarget target: String, data: String?) {
        flush(); breakRun()
    }
    func parser(_ parser: XMLParser, parseErrorOccurred parseError: any Error) { failed = true }
    func parser(_ parser: XMLParser, foundInternalEntityDeclarationWithName name: String, value: String?) {
        failed = true
    }
}
