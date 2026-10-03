// Part 2 follow-ups (spec 01 GF.6.7, GF.6.8, GF.6.10; DATA-323, DATA-324): the manual confirmations a person makes in
// the real AA.exe (Fixtures/xaml/wpf-capture/manual/, extracted by the GF.6.7 PowerShell script) checked against the
// automated WinCapture recipes and the WinFixtures goldens, so the day the captures are committed they are evidence
// rather than files nobody reads:
//
//   M-01…M-05 ↔ W01b/W02a/W03a/W04a/W05a   the real editor and the capture harness agree on every claim the pair
//                                            settles (root start tag S-1, table form S-4, hyperlink S-5,
//                                            Typography.Variants S-9, empty document S-10)
//   M-06 (W24)                               typed Greek survives; the xml:lang stamping is recorded
//   M-07 (W20) ↔ E13.X1                      the shipped build's checklist XLSX has the oracle's part sequence and
//                                            content-independent parts (text-lf)
//   M-09 ↔ W06                               the manual key-map record exists when W06 found no binding
//   M-capture                                the data.json AA.exe wrote round-trips byte-identically on the Mac in
//                                            the capture zone (01 §7.14-1) and holds exactly the extracted notes
//   W01b ↔ the Mac writer                    GF.6.10: a new Mac document's root start tag is W01b's, byte-for-byte
//
// `xml:lang` is ignored in the M ↔ W comparisons: AA.exe stamps typed runs with the input language, the programmatic
// typing of WinCapture does not (GF.6.4 Type(), W24).
import Foundation
import Testing
@testable import AACore

// MARK: - A minimal XML tree

/// Attributes by qualified name, children in document order; enough for the M ↔ W claims.
enum GoldXmlTree {
    struct Element: Sendable, Equatable {
        var name: String
        var attributes: [String: String]
        var children: [Child]
    }

    enum Child: Sendable, Equatable {
        case element(Element)
        case text(String)
    }

    struct Failure: Error, CustomStringConvertible {
        var message: String
        var description: String { "XML parse error: \(message)" }
    }

    private final class Builder: NSObject, XMLParserDelegate {
        var stack: [Element] = [Element(name: "#document", attributes: [:], children: [])]

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                    qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
            stack.append(Element(name: qName ?? elementName, attributes: attributeDict, children: []))
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
            guard stack.count > 1 else { return }
            let done = stack.removeLast()
            stack[stack.count - 1].children.append(.element(done))
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) { appendText(string) }

        func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) { appendText(String(decoding: CDATABlock, as: UTF8.self)) }

        private func appendText(_ s: String) {
            let i = stack.count - 1
            if case .text(let t)? = stack[i].children.last {
                stack[i].children[stack[i].children.count - 1] = .text(t + s)
            } else {
                stack[i].children.append(.text(s))
            }
        }
    }

    /// The root element of `data` (a leading UTF-8 BOM is accepted, as WPF's TextRange.Save writes one).
    static func parse(_ data: Data) throws -> Element {
        let builder = Builder()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = false
        parser.shouldResolveExternalEntities = false
        parser.delegate = builder
        guard parser.parse() else {
            throw Failure(message: parser.parserError.map { String(describing: $0) } ?? "unknown")
        }
        for child in builder.stack[0].children { if case .element(let e) = child { return e } }
        throw Failure(message: "no root element")
    }

    /// Every element named `name` (qualified, e.g. `Table`, `Table.Columns`), depth-first, `e` included.
    static func elements(named name: String, in e: Element) -> [Element] {
        var out: [Element] = e.name == name ? [e] : []
        for c in e.children { if case .element(let x) = c { out += elements(named: name, in: x) } }
        return out
    }

    /// Every value of attribute `attribute` anywhere under `e`, in document order.
    static func attributeValues(_ attribute: String, in e: Element) -> [String] {
        var out: [String] = e.attributes[attribute].map { [$0] } ?? []
        for c in e.children { if case .element(let x) = c { out += attributeValues(attribute, in: x) } }
        return out
    }

    /// The concatenated text content.
    static func text(_ e: Element) -> String {
        e.children.map { c -> String in
            switch c {
            case .text(let t): return t
            case .element(let x): return text(x)
            }
        }.joined()
    }

    /// A canonical serialisation: attributes sorted by name (minus `dropping`), text escaped, empty elements `<X />`.
    static func canonical(_ e: Element, dropping: Set<String> = []) -> String {
        let attrs = e.attributes.filter { !dropping.contains($0.key) }.sorted { $0.key < $1.key }
            .map { " \($0.key)=\"\(escape($0.value, attribute: true))\"" }.joined()
        if e.children.isEmpty { return "<\(e.name)\(attrs) />" }
        let inner = e.children.map { c -> String in
            switch c {
            case .text(let t): return escape(t, attribute: false)
            case .element(let x): return canonical(x, dropping: dropping)
            }
        }.joined()
        return "<\(e.name)\(attrs)>\(inner)</\(e.name)>"
    }

    static func escape(_ s: String, attribute: Bool) -> String {
        var out = ""
        for c in s.unicodeScalars {
            switch c {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"" where attribute: out += "&quot;"
            default: out.unicodeScalars.append(c)
            }
        }
        return out
    }
}

// MARK: - The manual captures and their checks

enum GoldManualCaptures {
    static var manualDir: URL { GoldPaths.wpfCapture.appending(path: "manual", directoryHint: .isDirectory) }
    static var available: Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: manualDir.path, isDirectory: &isDir) && isDir.boolValue
    }

    static func manualURL(_ name: String) -> URL { manualDir.appending(path: name) }
    static func captureURL(_ id: String) -> URL { GoldPaths.wpfCapture.appending(path: id + ".xaml") }
    static func captureExists(_ id: String) -> Bool { FileManager.default.fileExists(atPath: captureURL(id).path) }

    /// The files the GF.6.7 procedure always produces (M-08 is optional, M-09 conditional).
    static let required = ["M-01.xaml", "M-02.xaml", "M-03.xaml", "M-04.xaml", "M-05.xaml", "M-06.xaml",
                           "M-07.checklist.xlsx", "M-capture.data-json.golden.json"]

    static let ignoredAttributes: Set<String> = ["xml:lang"]

    /// One manual capture and the automated recipe that makes the same edit (GF.1.1 rows "W0n, M-0n").
    struct Pair: Sendable, CustomTestStringConvertible {
        enum Claim: String, Sendable {
            /// The root `<Section …>` start tag, byte-for-byte (05 §4.3.4 S-1, GF.6.10).
            case rootTag
            /// Root tag + the first `Table` element canonically equal (05 S-4).
            case table
            /// Root tag + the first `Hyperlink`'s attribute set (05 S-5).
            case hyperlink
            /// Root tag + every `Typography.Variants` value (05 S-9).
            case typographyVariants
            /// The whole document canonically equal (05 S-10, 05 §9 Q6).
            case wholeDocument
        }

        var manual: String
        var capture: String
        var claim: Claim
        var settles: String

        var testDescription: String { "\(manual) ↔ \(capture)" }
    }

    static let pairs: [Pair] = [
        Pair(manual: "M-01", capture: "W01b-S1-typed", claim: .rootTag, settles: "05 §4.3.4 S-1, 03 Q-9"),
        Pair(manual: "M-02", capture: "W02a-2x2-after-para", claim: .table, settles: "05 S-4"),
        Pair(manual: "M-03", capture: "W03a-empty-selection", claim: .hyperlink, settles: "05 S-5"),
        Pair(manual: "M-04", capture: "W04a-subscript", claim: .typographyVariants, settles: "05 S-9"),
        Pair(manual: "M-05", capture: "W05a-typed-then-deleted", claim: .wholeDocument, settles: "05 S-10, 05 §9 Q6"),
    ]

    /// The root element's start tag exactly as written (`<Section …>`), skipping a BOM, an XML declaration and
    /// comments; `>` inside a quoted attribute value does not end the tag. nil for an empty or tag-less text.
    static func rootStartTag(_ xaml: String) -> String? {
        var s = Substring(xaml)
        if s.first == "\u{FEFF}" { s = s.dropFirst() }
        while let lt = s.firstIndex(of: "<") {
            let after = s.index(after: lt)
            guard after < s.endIndex else { return nil }
            if s[after] == "?" || s[after] == "!" {
                guard let gt = s[after...].firstIndex(of: ">") else { return nil }
                s = s[s.index(after: gt)...]
                continue
            }
            var quote: Character?
            var i = after
            while i < s.endIndex {
                let c = s[i]
                if let q = quote { if c == q { quote = nil } }
                else if c == "\"" || c == "'" { quote = c }
                else if c == ">" { return String(s[lt...i]) }
                i = s.index(after: i)
            }
            return nil
        }
        return nil
    }

    /// Result of one M ↔ W comparison: blocking problems, plus a canonical whole-document difference that is only
    /// recorded (typing in the real app may split runs differently from the harness).
    struct Verdict: Sendable {
        var problems: [String] = []
        var recordedDifference: String?
    }

    static func compare(_ pair: Pair, manual: Data, capture: Data) -> Verdict {
        var v = Verdict()
        let m = String(decoding: manual, as: UTF8.self), w = String(decoding: capture, as: UTF8.self)
        let mEmpty = m.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\u{FEFF}"))).isEmpty
        let wEmpty = w.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\u{FEFF}"))).isEmpty
        if mEmpty || wEmpty {
            if mEmpty != wEmpty {
                v.problems.append("\(pair.manual) is \(mEmpty ? "empty" : "a document") but \(pair.capture) is \(wEmpty ? "empty" : "a document") (\(pair.settles))")
            }
            return v
        }
        let mt: GoldXmlTree.Element, wt: GoldXmlTree.Element
        do { mt = try GoldXmlTree.parse(manual) } catch { v.problems.append("\(pair.manual): \(error)"); return v }
        do { wt = try GoldXmlTree.parse(capture) } catch { v.problems.append("\(pair.capture): \(error)"); return v }

        let mc = GoldXmlTree.canonical(mt, dropping: ignoredAttributes)
        let wc = GoldXmlTree.canonical(wt, dropping: ignoredAttributes)
        if mc != wc {
            let off = GoldenMatcher.firstDifference(Array(wc.utf8), Array(mc.utf8)) ?? 0
            v.recordedDifference = "\(pair.manual) vs \(pair.capture): canonical documents differ at byte \(off)\n" +
                "  \(pair.capture): …\(GoldenMatcher.contextAround(Array(wc.utf8), off))…\n" +
                "  \(pair.manual): …\(GoldenMatcher.contextAround(Array(mc.utf8), off))…"
        }

        if pair.claim != .wholeDocument {
            let mr = rootStartTag(m), wr = rootStartTag(w)
            if mr != wr {
                v.problems.append("root start tag differs (\(pair.settles)): AA.exe wrote \(mr ?? "none"), WinCapture wrote \(wr ?? "none")")
            }
        }
        switch pair.claim {
        case .rootTag:
            break
        case .wholeDocument:
            if mc != wc { v.problems.append("the documents differ (\(pair.settles)) — \(v.recordedDifference ?? "")") }
        case .table:
            let ma = GoldXmlTree.elements(named: "Table", in: mt).first, wa = GoldXmlTree.elements(named: "Table", in: wt).first
            switch (ma, wa) {
            case (nil, _): v.problems.append("\(pair.manual) has no Table element (\(pair.settles))")
            case (_, nil): v.problems.append("\(pair.capture) has no Table element (\(pair.settles))")
            case let (a?, b?):
                let ac = GoldXmlTree.canonical(a, dropping: ignoredAttributes), bc = GoldXmlTree.canonical(b, dropping: ignoredAttributes)
                if ac != bc { v.problems.append("the Table differs (\(pair.settles)): AA.exe \(ac) vs WinCapture \(bc)") }
            }
        case .hyperlink:
            let ma = GoldXmlTree.elements(named: "Hyperlink", in: mt).first, wa = GoldXmlTree.elements(named: "Hyperlink", in: wt).first
            switch (ma, wa) {
            case (nil, _): v.problems.append("\(pair.manual) has no Hyperlink element (\(pair.settles))")
            case (_, nil): v.problems.append("\(pair.capture) has no Hyperlink element (\(pair.settles))")
            case let (a?, b?):
                let aa = a.attributes.filter { !ignoredAttributes.contains($0.key) }
                let ba = b.attributes.filter { !ignoredAttributes.contains($0.key) }
                if aa != ba {
                    v.problems.append("the Hyperlink attribute set differs (\(pair.settles)): AA.exe \(aa.sorted { $0.key < $1.key }) vs WinCapture \(ba.sorted { $0.key < $1.key })")
                }
            }
        case .typographyVariants:
            let a = GoldXmlTree.attributeValues("Typography.Variants", in: mt)
            let b = GoldXmlTree.attributeValues("Typography.Variants", in: wt)
            if a != b { v.problems.append("Typography.Variants differ (\(pair.settles)): AA.exe \(a) vs WinCapture \(b)") }
            if b.isEmpty { v.problems.append("\(pair.capture) carries no Typography.Variants — the capture did not exercise S-9") }
        }
        return v
    }

    // MARK: M-06 (W24)

    /// The Greek and the Latin text survive in the stored note; returns problems and the `xml:lang` values (recorded).
    static func m06(_ data: Data) -> (problems: [String], languages: [String]) {
        let tree: GoldXmlTree.Element
        do { tree = try GoldXmlTree.parse(data) } catch { return (["M-06: \(error)"], []) }
        let text = GoldXmlTree.text(tree)
        var problems: [String] = []
        for needle in ["Γειά σου", "ok"] where !text.contains(needle) {
            problems.append("M-06 lost the typed text \"\(needle)\" (stored text: \"\(text.prefix(80))\")")
        }
        return (problems, GoldXmlTree.attributeValues("xml:lang", in: tree))
    }

    // MARK: M-07 (W20)

    /// The content-independent parts of ChecklistExporter.ExportXlsx (AA/Services/ChecklistExporter.cs:133-138);
    /// `xl/workbook.xml` carries the procedure name and `xl/worksheets/sheet1.xml` the rows, so those are recorded.
    static let w20StaticParts = ["[Content_Types].xml", "_rels/.rels", "xl/_rels/workbook.xml.rels", "xl/styles.xml"]

    /// Compares the shipped build's XLSX with the oracle's E13.X1 archive: same part sequence; the static parts equal
    /// modulo newline (text-lf). The record names the parts that use CRLF (the newline the real product ships).
    static func w20(xlsx: Data, oracle: GoldZipManifest, oraclePayload: (String) throws -> Data) -> Verdict {
        var v = Verdict()
        let actual: GoldZipManifest
        let reader: ZipReader
        do {
            actual = try GoldZipManifest(zip: xlsx, orderSignificant: true)
            reader = try ZipReader(data: xlsx)
        } catch {
            v.problems.append("M-07.checklist.xlsx is not a readable ZIP: \(error)")
            return v
        }
        let names = actual.entries.map(\.name), expected = oracle.entries.map(\.name)
        if names != expected { v.problems.append("part sequence differs (11 §4.5): AA.exe \(names) vs WinFixtures \(expected)") }
        var crlf: [String] = []
        for e in actual.entries where !e.isDirectory {
            guard let info = reader.entry(named: e.name), let bytes = try? reader.data(for: info) else { continue }
            if String(decoding: bytes, as: UTF8.self).contains("\r\n") { crlf.append(e.name) }
        }
        for part in w20StaticParts {
            guard let info = reader.entry(named: part), let mine = try? reader.data(for: info) else {
                v.problems.append("\(part) is missing from M-07.checklist.xlsx"); continue
            }
            guard let payload = oracle.entries.first(where: { $0.name == part })?.payload else {
                v.problems.append("\(part) has no payload in the E13.X1 manifest"); continue
            }
            let theirs: Data
            do { theirs = try oraclePayload(payload) } catch { v.problems.append("\(part): oracle payload \(payload) unreadable"); continue }
            if let m = GoldenMatcher.byteMismatch(lf(theirs), lf(mine)) {
                v.problems.append("\(part) differs from the oracle modulo newline (text-lf, W20): \(m)")
            }
        }
        v.recordedDifference = crlf.isEmpty ? "W20: every part uses LF" : "W20: CRLF in \(crlf.joined(separator: ", "))"
        return v
    }

    /// `\r\n` → `\n` (the text-lf mode of GF.4.9).
    static func lf(_ d: Data) -> Data {
        Data(String(decoding: d, as: UTF8.self).replacingOccurrences(of: "\r\n", with: "\n").utf8)
    }

    /// The E13.X1 zip manifest and a payload loader from the WinFixtures goldens (nil when not generated yet).
    static func e13X1() -> (GoldZipManifest, (String) throws -> Data)? {
        let index = GoldFixtureIndex.winfixtures
        guard let c = index.manifest?.cases.first(where: { $0.id == "E13.X1" }),
              let ref = c.outputs.first(where: { $0.compare == .zipManifestOrdered || $0.file.hasSuffix(".zip-manifest.golden.json") }),
              let data = try? index.data(ref.file), let json = try? JSONParser.parse(data),
              let manifest = try? GoldZipManifest(json: json) else { return nil }
        let folder = (ref.file as NSString).deletingLastPathComponent
        return (manifest, { name in try index.data(folder.isEmpty ? name : folder + "/" + name) })
    }

    // MARK: M-09

    /// M-09 is required exactly when W06 recorded no key binding (GF.6.7).
    static func m09(gestures: Data?, m09Exists: Bool) -> [String] {
        guard !m09Exists else { return [] }
        guard let gestures else { return ["neither W06-gestures.json nor manual/M-09.keys.md exists (CONT-030 key map unsettled)"] }
        guard let rows = try? JSONParser.parse(gestures).arrayValue else { return ["W06-gestures.json is not a JSON array"] }
        return rows.isEmpty ? ["W06 recorded no key binding, so manual/M-09.keys.md is required (GF.6.7)"] : []
    }

    // MARK: M-capture

    /// The capture zone: `manual/M-capture.timezone.txt` (IANA id), else the WinCapture manifest's `ianaTimeZone`.
    static func captureZone(timezoneFile: String?, manifestRuns: [JSONObject]) -> TimeZone? {
        if let id = timezoneFile?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty, let z = TimeZone(identifier: id) { return z }
        for run in manifestRuns {
            if let id = run["ianaTimeZone"]?.stringValue, let z = TimeZone(identifier: id) { return z }
        }
        return nil
    }

    /// Load + SerializeForSave on the Mac in `zone`; nil when byte-identical.
    @MainActor
    static func roundTrip(_ original: Data, zone: TimeZone) -> String? {
        let folder = TempFolder("gold-m-capture")
        let ds = DataStore(appFolder: folder.url, secrets: InMemorySecretStore(), clock: GoldZoneClock(zone: zone))
        ds.loadSettings()
        let copy = folder.file("data.json")
        do { try original.write(to: copy) } catch { return "scratch copy failed: \(error)" }
        do {
            let resaved = try ds.serializeForSave(try ds.loadFrom(copy))
            return GoldenMatcher.byteMismatch(original, resaved).map { "M-capture does not re-save byte-identically: \($0)" }
        } catch {
            return "M-capture does not load/save on the Mac: \(error)"
        }
    }

    /// Every `M-xx` task's RichTextXaml equals the extracted `manual/M-xx.xaml` (the extraction script's contract).
    static func extractionProblems(dataJSON: Data, xaml: (String) -> Data?) -> [String] {
        guard let root = try? JSONParser.parse(dataJSON), let tasks = root.objectValue?["Tasks"]?.arrayValue else {
            return ["M-capture.data-json.golden.json has no Tasks array"]
        }
        var out: [String] = []
        var seen = Set<String>()
        for t in tasks.compactMap(\.objectValue) {
            guard let name = t["Name"]?.stringValue, name.hasPrefix("M-") else { continue }
            seen.insert(name)
            let stored = t["Container"]?.objectValue?["RichTextXaml"]?.stringValue ?? ""
            guard let file = xaml(name) else {
                if name.count == 4 { out.append("\(name): task present in M-capture but manual/\(name).xaml is missing") }
                continue
            }
            if String(decoding: file, as: UTF8.self) != stored {
                out.append("\(name): manual/\(name).xaml differs from the task's RichTextXaml in M-capture")
            }
        }
        for n in 1...6 {
            let name = String(format: "M-%02d", n)
            if !seen.contains(name) { out.append("M-capture has no task named \(name)") }
        }
        return out
    }
}

// MARK: - Suites

@Suite("WinFixtures — manual confirmations in the real AA.exe (DATA-323, W20, W24)", .tags(.goldWinFixtures),
       .enabled(if: GoldManualCaptures.available,
                "manual captures are absent: follow mac/Tools/WinCapture/README.md §4 on Windows and commit Fixtures/xaml/wpf-capture/manual/"))
struct GoldManualCaptureTests {
    @Test("the GF.6.7 procedure's files are all present")
    func present() {
        for f in GoldManualCaptures.required where !FileManager.default.fileExists(atPath: GoldManualCaptures.manualURL(f).path) {
            Issue.record(Comment(rawValue: "manual/\(f) is missing (GF.6.7)"))
        }
    }

    @Test("AA.exe and WinCapture agree on the claim each pair settles", arguments: GoldManualCaptures.pairs)
    func pair(_ p: GoldManualCaptures.Pair) throws {
        let m = GoldManualCaptures.manualURL(p.manual + ".xaml")
        guard FileManager.default.fileExists(atPath: m.path) else { return }     // reported by present()
        guard GoldManualCaptures.captureExists(p.capture) else {
            Issue.record(Comment(rawValue: "\(p.capture).xaml is missing: run WinCapture all before comparing \(p.manual)")); return
        }
        let v = GoldManualCaptures.compare(p, manual: try Data(contentsOf: m), capture: try Data(contentsOf: GoldManualCaptures.captureURL(p.capture)))
        if let d = v.recordedDifference { Attachment.record(Data(d.utf8), named: "\(p.manual).vs.\(p.capture).txt") }
        for problem in v.problems { Issue.record(Comment(rawValue: "\(p.manual) ↔ \(p.capture): \(problem)")) }
    }

    @Test("M-06: typed Greek survives; the xml:lang stamping is recorded (W24)")
    func m06() throws {
        let url = GoldManualCaptures.manualURL("M-06.xaml")
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let r = GoldManualCaptures.m06(try Data(contentsOf: url))
        Attachment.record(Data("xml:lang values: \(r.languages)".utf8), named: "M-06.xml-lang.txt")
        for p in r.problems { Issue.record(Comment(rawValue: p)) }
    }

    @Test("M-07 (W20): the shipped build's XLSX matches the E13.X1 oracle modulo newline")
    func w20() throws {
        let url = GoldManualCaptures.manualURL("M-07.checklist.xlsx")
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        guard let (oracle, payload) = GoldManualCaptures.e13X1() else {
            Issue.record("E13.X1 goldens are absent: run Scripts/fixtures.sh generate before comparing W20"); return
        }
        let v = GoldManualCaptures.w20(xlsx: try Data(contentsOf: url), oracle: oracle, oraclePayload: payload)
        if let d = v.recordedDifference { Attachment.record(Data(d.utf8), named: "W20.newlines.txt") }
        for p in v.problems { Issue.record(Comment(rawValue: "W20: \(p)")) }
    }

    @Test("M-09 exists when W06 recorded no key binding")
    func m09() {
        let gestures = try? Data(contentsOf: GoldPaths.wpfCapture.appending(path: "W06-gestures.json"))
        let exists = FileManager.default.fileExists(atPath: GoldManualCaptures.manualURL("M-09.keys.md").path)
        for p in GoldManualCaptures.m09(gestures: gestures, m09Exists: exists) { Issue.record(Comment(rawValue: p)) }
    }

    @MainActor
    @Test("M-capture: AA.exe's data.json re-saves byte-identically on the Mac (01 §7.14-1) and holds the extracted notes")
    func mCapture() throws {
        let url = GoldManualCaptures.manualURL("M-capture.data-json.golden.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let original = try Data(contentsOf: url)
        let tzText = (try? Data(contentsOf: GoldManualCaptures.manualURL("M-capture.timezone.txt"))).map { String(decoding: $0, as: UTF8.self) }
        if let zone = GoldManualCaptures.captureZone(timezoneFile: tzText, manifestRuns: GoldFixtureIndex.wpfCapture.manifest?.runs ?? []) {
            if let p = GoldManualCaptures.roundTrip(original, zone: zone) { Issue.record(Comment(rawValue: p)) }
        } else {
            Issue.record("the capture zone is unknown: commit manual/M-capture.timezone.txt (README §4) so the Local stamps re-save in the zone AA.exe wrote them")
        }
        let problems = GoldManualCaptures.extractionProblems(dataJSON: original) { name in
            try? Data(contentsOf: GoldManualCaptures.manualURL(name + ".xaml"))
        }
        for p in problems { Issue.record(Comment(rawValue: p)) }
    }
}

@Suite("WinFixtures — W01b root start tag on the Mac writer (GF.6.10)", .tags(.goldWinFixtures),
       .enabled(if: GoldManualCaptures.captureExists("W01b-S1-typed"), GoldFixtureIndex.absentCaptureMessage))
struct GoldW01bRootTagTests {
    @MainActor
    @Test("a new Mac document's root start tag is W01b's byte-for-byte (05 §4.3.7 rule 2)",
          .enabled(if: ContractStatus.isImplemented(.wRich), "needs W-RICH's XamlWriter"))
    func newDocumentRoot() throws {
        let w01b = String(decoding: try Data(contentsOf: GoldManualCaptures.captureURL("W01b-S1-typed")), as: UTF8.self)
        let mac = XamlWriter.write(NSAttributedString(string: "Check the main engine oil level."),
                                   metadata: RichTextMetadata(context: .containerEditor), context: .containerEditor)
        let expected = try #require(GoldManualCaptures.rootStartTag(w01b))
        #expect(GoldManualCaptures.rootStartTag(mac) == expected)
    }
}

// MARK: - Self-tests on synthetic captures (always on)

@Suite("WinFixtures harness — manual-capture checks (GF.6.7, GF.6.8)", .tags(.goldWinFixtures))
struct GoldManualCaptureHarnessTests {
    static let ns = #"xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation""#
    static let root = ##"<Section \##(ns) xml:space="preserve" TextAlignment="Left" LineHeight="Auto" IsHyphenationEnabled="False" xml:lang="en-us" FlowDirection="LeftToRight" NumberSubstitution.CultureSource="User" NumberSubstitution.Substitution="AsCulture" FontFamily="Consolas" FontStyle="Normal" FontWeight="Normal" FontStretch="Normal" FontSize="14" Foreground="#FF1A1A1A" Typography.StandardLigatures="True">"##

    static func doc(_ body: String, root: String = root) -> Data { Data(("\u{FEFF}" + root + body + "</Section>").utf8) }

    @Test("root start tag: BOM, declaration, comment and a quoted > are handled")
    func rootTag() {
        #expect(GoldManualCaptures.rootStartTag("\u{FEFF}<Section a=\"1\">x</Section>") == "<Section a=\"1\">")
        #expect(GoldManualCaptures.rootStartTag("<?xml version=\"1.0\"?><!-- c --><R t=\"a>b\" u='>'/>") == "<R t=\"a>b\" u='>'/>")
        #expect(GoldManualCaptures.rootStartTag("") == nil)
        #expect(GoldManualCaptures.rootStartTag("plain text") == nil)
    }

    @Test("M-01: equal root tags pass; a different root attribute fails; body differences are only recorded")
    func m01() {
        let p = GoldManualCaptures.pairs[0]
        let w = Self.doc(#"<Paragraph><Run>Check the </Run><Run FontWeight="Bold">main engine</Run></Paragraph>"#)
        let typed = Self.doc(#"<Paragraph><Run xml:lang="en-us">Check the </Run><Run FontWeight="Bold" xml:lang="en-us">main engine</Run><Run xml:lang="en-us"></Run></Paragraph>"#)
        let ok = GoldManualCaptures.compare(p, manual: typed, capture: w)
        #expect(ok.problems.isEmpty, "\(ok.problems)")
        #expect(ok.recordedDifference != nil)
        let other = Self.doc("<Paragraph><Run>x</Run></Paragraph>", root: Self.root.replacingOccurrences(of: "FontSize=\"14\"", with: "FontSize=\"13\""))
        #expect(GoldManualCaptures.compare(p, manual: other, capture: w).problems.first?.contains("root start tag differs") == true)
    }

    @Test("M-02: the Table must match canonically (xml:lang ignored); BorderThickness form differences fail")
    func m02() {
        let p = GoldManualCaptures.pairs[1]
        let table = { (bt: String) in
            ##"<Table CellSpacing="0" Margin="0,4,0,4"><Table.Columns><TableColumn /><TableColumn /></Table.Columns><TableRowGroup><TableRow><TableCell BorderBrush="#FF9AA0A6" BorderThickness="\##(bt)" Padding="3,1,3,1" FontWeight="Bold"><Paragraph><Run xml:lang="en-us"></Run></Paragraph></TableCell></TableRow></TableRowGroup></Table>"##
        }
        let w = Self.doc(#"<Paragraph><Run>Before table</Run></Paragraph>"# + table("0.6,0.6,0.6,0.6").replacingOccurrences(of: #" xml:lang="en-us""#, with: ""))
        let m = Self.doc("<Paragraph />" + table("0.6,0.6,0.6,0.6"))
        #expect(GoldManualCaptures.compare(p, manual: m, capture: w).problems.isEmpty)
        let bad = Self.doc("<Paragraph />" + table("0.6"))
        #expect(GoldManualCaptures.compare(p, manual: bad, capture: w).problems.contains { $0.contains("the Table differs") })
        let none = Self.doc("<Paragraph />")
        #expect(GoldManualCaptures.compare(p, manual: none, capture: w).problems.contains { $0.contains("has no Table") })
    }

    @Test("M-03 hyperlink attribute set; M-04 Typography.Variants; M-05 whole empty document")
    func m03m04m05() {
        let link = { (attrs: String) in Self.doc(#"<Paragraph><Run>See </Run><Hyperlink \#(attrs)><Run>https://www.imo.org/</Run></Hyperlink></Paragraph>"#) }
        let p3 = GoldManualCaptures.pairs[2]
        #expect(GoldManualCaptures.compare(p3, manual: link(#"NavigateUri="https://www.imo.org/" xml:lang="en-us""#),
                                           capture: link(#"NavigateUri="https://www.imo.org/""#)).problems.isEmpty)
        #expect(!GoldManualCaptures.compare(p3, manual: link(##"NavigateUri="https://www.imo.org/" Foreground="#FF0000FF""##),
                                            capture: link(#"NavigateUri="https://www.imo.org/""#)).problems.isEmpty)

        let p4 = GoldManualCaptures.pairs[3]
        let sub = { (v: String) in Self.doc(#"<Paragraph><Run>H</Run><Run Typography.Variants="\#(v)">2</Run><Run>O</Run></Paragraph>"#) }
        #expect(GoldManualCaptures.compare(p4, manual: sub("Subscript"), capture: sub("Subscript")).problems.isEmpty)
        #expect(GoldManualCaptures.compare(p4, manual: sub("Inferior"), capture: sub("Subscript")).problems.contains { $0.contains("Typography.Variants differ") })

        let p5 = GoldManualCaptures.pairs[4]
        let empty = Self.doc("<Paragraph />")
        #expect(GoldManualCaptures.compare(p5, manual: empty, capture: empty).problems.isEmpty)
        #expect(!GoldManualCaptures.compare(p5, manual: Self.doc("<Paragraph><Run /></Paragraph>"), capture: empty).problems.isEmpty)
        #expect(GoldManualCaptures.compare(p5, manual: Data(), capture: Data()).problems.isEmpty)
        #expect(GoldManualCaptures.compare(p5, manual: Data(), capture: empty).problems.first?.contains("is empty but") == true)
    }

    @Test("M-06 keeps the typed Greek; xml:lang values are collected")
    func m06() {
        let ok = Self.doc(#"<Paragraph><Run xml:lang="el-gr">Γειά σου</Run><Run xml:lang="en-us"> ok</Run></Paragraph>"#)
        let r = GoldManualCaptures.m06(ok)
        #expect(r.problems.isEmpty)
        #expect(r.languages == ["en-us", "el-gr", "en-us"])
        #expect(GoldManualCaptures.m06(Self.doc("<Paragraph><Run>?? ok</Run></Paragraph>")).problems.count == 1)
    }

    static func xlsx(_ parts: [(String, String)]) throws -> Data {
        let folder = TempFolder("gold-w20")
        let url = folder.file("x.xlsx")
        let z = try ZipWriter(url: url)
        for (n, t) in parts { try z.addData(Data(t.utf8), named: n, modified: nil) }
        try z.finish()
        return try Data(contentsOf: url)
    }

    static let lfParts: [(String, String)] = [
        ("[Content_Types].xml", "<Types>\n<Default/>\n</Types>"),
        ("_rels/.rels", "<Relationships>\n<Relationship/>\n</Relationships>"),
        ("xl/workbook.xml", "<workbook>\n<sheet name=\"Pump\"/>\n</workbook>"),
        ("xl/_rels/workbook.xml.rels", "<Relationships>\n</Relationships>"),
        ("xl/styles.xml", "<styleSheet>\n<fonts/>\n</styleSheet>"),
        ("xl/worksheets/sheet1.xml", "<worksheet>\n<row r=\"1\"/>\n</worksheet>"),
    ]

    @Test("W20: same sequence and static parts modulo newline pass; content and order differences fail")
    func w20() throws {
        let oracleZip = try Self.xlsx(Self.lfParts)
        var oracle = try GoldZipManifest(zip: oracleZip, orderSignificant: true)
        for i in oracle.entries.indices { oracle.entries[i].payload = oracle.entries[i].name }
        let payloads = Dictionary(uniqueKeysWithValues: Self.lfParts.map { ($0.0, Data($0.1.utf8)) })
        let load: (String) throws -> Data = { name in
            guard let d = payloads[name] else { throw GoldReproError.missingInput(name) }
            return d
        }
        // The shipped exe: CRLF everywhere, another procedure name and other rows.
        let shipped = Self.lfParts.map { (n, t) -> (String, String) in
            let body = n == "xl/workbook.xml" ? t.replacingOccurrences(of: "Pump", with: "Fire drill") : n.hasSuffix("sheet1.xml") ? t + "<x/>" : t
            return (n, body.replacingOccurrences(of: "\n", with: "\r\n"))
        }
        let ok = GoldManualCaptures.w20(xlsx: try Self.xlsx(shipped), oracle: oracle, oraclePayload: load)
        #expect(ok.problems.isEmpty, "\(ok.problems)")
        #expect(ok.recordedDifference?.contains("CRLF in [Content_Types].xml") == true)

        var styled = shipped
        styled[4].1 = "<styleSheet>\r\n<fonts count=\"2\"/>\r\n</styleSheet>"
        #expect(GoldManualCaptures.w20(xlsx: try Self.xlsx(styled), oracle: oracle, oraclePayload: load).problems
                .contains { $0.hasPrefix("xl/styles.xml differs") })
        #expect(GoldManualCaptures.w20(xlsx: try Self.xlsx(Array(shipped.reversed())), oracle: oracle, oraclePayload: load).problems
                .contains { $0.hasPrefix("part sequence differs") })
    }

    @Test("M-09 is required only when W06 recorded no binding")
    func m09() {
        #expect(GoldManualCaptures.m09(gestures: Data("[]".utf8), m09Exists: false).count == 1)
        #expect(GoldManualCaptures.m09(gestures: Data("[]".utf8), m09Exists: true).isEmpty)
        #expect(GoldManualCaptures.m09(gestures: Data(#"[{"command":"ToggleBold"}]"#.utf8), m09Exists: false).isEmpty)
        #expect(GoldManualCaptures.m09(gestures: nil, m09Exists: false).count == 1)
    }

    @Test("capture zone: the timezone file wins, then the WinCapture manifest; unknown ids are ignored")
    func zone() throws {
        let run = try #require(try JSONParser.parse(#"{"platform":"windows","timeZone":"GTB Standard Time","ianaTimeZone":"Europe/Athens"}"#).objectValue)
        #expect(GoldManualCaptures.captureZone(timezoneFile: "Asia/Kolkata\n", manifestRuns: [run])?.identifier == "Asia/Kolkata")
        #expect(GoldManualCaptures.captureZone(timezoneFile: nil, manifestRuns: [run])?.identifier == "Europe/Athens")
        #expect(GoldManualCaptures.captureZone(timezoneFile: "GTB Standard Time", manifestRuns: []) == nil)
    }

    @MainActor
    @Test("M-capture: a data.json written in Athens re-saves byte-identically in Athens; the extraction is checked")
    func mCapture() throws {
        let athens = try #require(TimeZone(identifier: "Europe/Athens"))
        let folder = TempFolder("gold-m-capture-synth")
        let ds = DataStore(appFolder: folder.url, secrets: InMemorySecretStore(), clock: GoldZoneClock(zone: athens))
        let data = AppData()
        var notes: [String: String] = [:]
        for n in 1...6 {
            let name = String(format: "M-%02d", n)
            let t = TaskItem(id: UUID(), name: name)
            t.container.richTextXaml = "<Section xml:space=\"preserve\"><Paragraph><Run>\(name) é</Run></Paragraph></Section>"
            notes[name] = t.container.richTextXaml
            data.tasks.append(t)
        }
        data.lastModified = GoldDates.dLM
        let bytes = try ds.serializeForSave(data)
        #expect(GoldManualCaptures.roundTrip(bytes, zone: athens) == nil)
        var spaced = bytes
        spaced.append(contentsOf: Array("\n".utf8))
        #expect(GoldManualCaptures.roundTrip(spaced, zone: athens)?.contains("byte-identically") == true)

        #expect(GoldManualCaptures.extractionProblems(dataJSON: bytes) { notes[$0].map { Data($0.utf8) } }.isEmpty)
        let wrong = GoldManualCaptures.extractionProblems(dataJSON: bytes) { $0 == "M-03" ? Data("x".utf8) : notes[$0].map { Data($0.utf8) } }
        #expect(wrong == ["M-03: manual/M-03.xaml differs from the task's RichTextXaml in M-capture"])
        let missing = GoldManualCaptures.extractionProblems(dataJSON: bytes) { $0 == "M-02" ? nil : notes[$0].map { Data($0.utf8) } }
        #expect(missing == ["M-02: task present in M-capture but manual/M-02.xaml is missing"])
    }
}
