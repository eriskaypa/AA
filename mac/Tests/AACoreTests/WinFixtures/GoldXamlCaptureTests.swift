// Part 2 (GF.6, DATA-321/325): the WPF captures in Fixtures/xaml/wpf-capture/ (written by mac/Tools/WinCapture on
// Windows) against W-RICH's XAML reader/writer and HTML converter, and the W23 load-check results of the Mac's own
// XAML (Fixtures/xaml/mac-roundtrip/, written by `WinCapture load-check` from Fixtures/mac-out/xaml/).
//
// Role `xaml` (macExpectation same): the Mac reads the WPF-saved XAML and writes it back; the result must be
// canonically equal (05 §XD.2.10 "same"). Role `converter`: HTMLToXAML.convert(inputs.html) must equal
// HtmlToXamlConverter.Convert. Outputs marked `mac: false` (raw WPF behaviour, paste replicas, SIRE generator
// output) are the Windows record only. Everything needs W-RICH's real code (`requires: .wRich`).
import AppKit
import Foundation
import Testing
@testable import AACore

@MainActor
enum GoldXamlFamily {
    /// Every W capture is read in the container editor's context except the SIRE pane's edited body (W16).
    static func context(for c: GoldFixtureCase) -> XamlContext {
        c.id.hasPrefix("W16-edited-body") ? .sirePane : .containerEditor
    }

    /// WPF XAML → Mac model → Mac XAML.
    static func roundTrip(_ xaml: String, context: XamlContext) throws -> Data {
        switch XamlReader.read(xaml, context: context) {
        case .empty: return Data(XamlWriter.emptyDocument().utf8)
        case .document(let text, let metadata): return Data(XamlWriter.write(text, metadata: metadata, context: context).utf8)
        case .unparseable: throw GoldReproError.unexpected("the Mac XAML reader cannot parse the WPF output (the editor would withhold saving, CONT-006)")
        }
    }

    static func reproduce(_ ctx: GoldCaseContext) throws -> GoldActual {
        let c = ctx.fixtureCase
        var out: GoldActual = [:]
        for ref in c.outputs where ref.macCompared {
            switch ref.role {
            case "converter":
                guard let html = ctx.inlineString("html") else { throw GoldReproError.missingInput("html") }
                let mac = HTMLToXAML.convert(html)
                let golden = try ctx.goldenData(ref.file)
                // An empty conversion (no body content) has no XML to canonicalise: both must be empty.
                if golden.isEmpty && mac.isEmpty { out[ref.role] = .skip("both conversions are empty") } else { out[ref.role] = .bytes(Data(mac.utf8)) }
            default:
                let wpf = String(decoding: try ctx.goldenData(ref.file), as: UTF8.self)
                out[ref.role] = .bytes(try roundTrip(wpf, context: context(for: c)))
            }
        }
        return out
    }

    static let table: GoldReproducerTable = {
        var entries: [String: GoldReproducer] = [:]
        for n in 1...23 {
            entries[String(format: "W%02d", n)] = GoldReproducer(requires: .wRich) { ctx in try reproduce(ctx) }
        }
        return GoldReproducerTable(entries: entries)
    }()
}

@Suite("WinFixtures — WPF captures (DATA-321)", .tags(.goldWinFixtures),
       .enabled(if: GoldFixtureIndex.wpfCapture.available, GoldFixtureIndex.absentCaptureMessage))
struct GoldXamlCaptureTests {
    @Test("GF.6 capture", arguments: GoldFixtureIndex.wpfCapture.cases(family: "xaml"))
    func capture(_ c: GoldFixtureCase) async {
        await GoldCaseRunner.run(c, index: .wpfCapture, table: GoldXamlFamily.table)
    }

    @Test("the culture-invariance recordings agree (GF.6.5: el-GR and th-TH write the en-US bytes)")
    func cultureInvariance() throws {
        let index = GoldFixtureIndex.wpfCapture
        guard index.exists("culture-invariance.json") else {
            Issue.record("culture-invariance.json is missing from the capture (WinCapture all writes it)"); return
        }
        for p in try GoldXamlFamily.invarianceProblems(try index.data("culture-invariance.json")) { Issue.record(Comment(rawValue: p)) }
    }
}

extension GoldXamlFamily {
    /// Rows of WinCapture's culture-invariance.json that are not byte-identical to en-US (or a culture run that threw).
    nonisolated static func invarianceProblems(_ data: Data) throws -> [String] {
        guard let rows = try JSONParser.parse(data).arrayValue else { return ["culture-invariance.json is not an array"] }
        var out: [String] = []
        for row in rows.compactMap(\.objectValue) {
            let culture = row["culture"]?.stringValue ?? "?"
            if let e = row["error"]?.stringValue { out.append("\(culture): the recipes threw — \(e.prefix(300))") }
            else if row["identicalToEnUS"]?.boolValue != true { out.append("\(culture): \(row["file"]?.stringValue ?? "?") differs from en-US") }
        }
        if rows.isEmpty { out.append("culture-invariance.json is empty") }
        return out
    }
}

/// W23 (DATA-325): WPF loads every Mac XAML output and re-saves it.
enum GoldMacRoundtrip {
    static var loadCheck: URL { GoldPaths.macRoundtrip.appending(path: "load-check.json") }
    static var available: Bool { FileManager.default.fileExists(atPath: loadCheck.path) }

    struct Row: Equatable { var name: String; var ok: Bool; var detail: String }

    static func rows(_ data: Data) throws -> [Row] {
        guard let items = try JSONParser.parse(data).arrayValue else { throw GoldReproError.unexpected("load-check.json is not an array") }
        return items.compactMap { v in
            guard let o = v.objectValue, let name = o["name"]?.stringValue else { return nil }
            return Row(name: name, ok: o["ok"]?.boolValue ?? false, detail: o["detail"]?.stringValue ?? "")
        }
    }

    /// Problems in a load-check result against the Mac files it was run on.
    static func problems(rows: [Row], macNames: [String]) -> [String] {
        var out = rows.filter { !$0.ok }.map { "\($0.name): WPF refused the Mac XAML — \($0.detail)" }
        let checked = Set(rows.map(\.name))
        for name in macNames where !checked.contains(name) { out.append("\(name): not load-checked (rerun WinCapture load-check)") }
        if rows.isEmpty { out.append("load-check.json lists no file") }
        return out
    }

    /// Occurrences of the lock-sentinel colour (05 §4.4), case-insensitive.
    static func sentinelCount(_ xaml: Data) -> Int {
        String(decoding: xaml, as: UTF8.self).uppercased().components(separatedBy: "#FFFFE699").count - 1
    }

    static var macNames: [String] {
        let dir = GoldPaths.macOut.appending(path: "xaml")
        return ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [])
            .filter { $0.hasSuffix(".xaml") }.map { String($0.dropLast(5)) }.sorted()
    }
}

@Suite("WinFixtures — WPF load-check of Mac XAML (DATA-325, W23)", .tags(.goldWinFixtures),
       .enabled(if: GoldMacRoundtrip.available, "W23 results are absent: run `WinCapture load-check` on Windows over Fixtures/mac-out/xaml (mac/Tools/WinCapture/README.md) and commit Fixtures/xaml/mac-roundtrip/"))
struct GoldMacRoundtripTests {
    @Test("WPF loaded every Mac XAML file")
    func loadCheck() throws {
        let rows = try GoldMacRoundtrip.rows(try Data(contentsOf: GoldMacRoundtrip.loadCheck))
        for p in GoldMacRoundtrip.problems(rows: rows, macNames: GoldMacRoundtrip.macNames) { Issue.record(Comment(rawValue: p)) }
    }

    @Test("WPF's re-save keeps every lock sentinel (#FFFFE699); other canonical differences are recorded")
    func sentinelsKept() throws {
        let dir = GoldPaths.macOut.appending(path: "xaml")
        for name in GoldMacRoundtrip.macNames {
            let resaved = GoldPaths.macRoundtrip.appending(path: name + ".wpf-resaved.xaml")
            guard FileManager.default.fileExists(atPath: resaved.path) else { continue }
            let mac = try Data(contentsOf: dir.appending(path: name + ".xaml")), wpf = try Data(contentsOf: resaved)
            #expect(GoldMacRoundtrip.sentinelCount(mac) == GoldMacRoundtrip.sentinelCount(wpf),
                    "\(name): WPF's re-save changed the number of lock sentinels")
            if let diff = GoldXMLCanonicalizer.difference(golden: mac, actual: wpf) {
                Attachment.record(Data("\(diff)".utf8), named: "\(name).roundtrip-difference.txt")
            }
        }
    }

    @MainActor
    @Test("WPF's re-save keeps the Mac document's text (needs W-RICH's reader)",
          .enabled(if: ContractStatus.isImplemented(.wRich)))
    func resavedText() throws {
        let dir = GoldPaths.macOut.appending(path: "xaml")
        for name in GoldMacRoundtrip.macNames {
            let resaved = GoldPaths.macRoundtrip.appending(path: name + ".wpf-resaved.xaml")
            guard FileManager.default.fileExists(atPath: resaved.path) else { continue }
            func text(_ url: URL) throws -> String? {
                switch XamlReader.read(String(decoding: try Data(contentsOf: url), as: UTF8.self), context: .containerEditor) {
                case .empty: return ""
                case .document(let s, _): return s.string
                case .unparseable: return nil
                }
            }
            let mac = try text(dir.appending(path: name + ".xaml")), wpf = try text(resaved)
            #expect(mac != nil && mac == wpf, "\(name): text differs after the WPF load/save round trip")
        }
    }
}

@Suite("WinFixtures harness — XAML capture plumbing", .tags(.goldWinFixtures))
struct GoldXamlHarnessTests {
    @Test("capture ids map to their recipe group; W16's edited body uses the SIRE context")
    @MainActor
    func lookup() throws {
        let r = GoldSyntheticRoot()
        let rec = { (id: String) in
            #"{"id":"\#(id)","family":"xaml","title":"t","platform":"windows","compare":"xml-canonical","outputs":[{"role":"xaml","file":"\#(id).xaml"}],"macExpectation":{"kind":"same"}}"#
        }
        let index = try r.manifest([rec("W01a-pristine"), rec("W12-H-01.converter"), rec("W16-edited-body-1.1.1")])
        let cases = index.cases(family: "xaml")
        #expect(cases.count == 3)
        for c in cases { #expect(GoldXamlFamily.table.reproducer(for: c)?.requires == .wRich, "\(c.id)") }
        #expect(GoldXamlFamily.context(for: cases[2]) == .sirePane)
        #expect(GoldXamlFamily.context(for: cases[0]) == .containerEditor)
    }

    @Test("load-check results: failures and unchecked Mac files are reported")
    func loadCheckProblems() throws {
        let rows = try GoldMacRoundtrip.rows(Data(#"[{"name":"lists","ok":true,"detail":"a"},{"name":"tables","ok":false,"detail":"XamlParseException: x"}]"#.utf8))
        #expect(rows.count == 2)
        let p = GoldMacRoundtrip.problems(rows: rows, macNames: ["empty", "lists", "tables"])
        #expect(p.count == 2)
        #expect(p.contains { $0.hasPrefix("tables: WPF refused") })
        #expect(p.contains { $0.hasPrefix("empty: not load-checked") })
        #expect(GoldMacRoundtrip.problems(rows: [], macNames: []) == ["load-check.json lists no file"])
        #expect(GoldMacRoundtrip.sentinelCount(Data("<Run Background=\"#ffffe699\">a</Run><Run Background=\"#FFFFE699\">b</Run>".utf8)) == 2)
    }

    @Test("culture-invariance rows that differ or threw are reported")
    func invariance() throws {
        let json = #"[{"culture":"el-GR","file":"W01a-pristine.xaml","identicalToEnUS":true},{"culture":"th-TH","file":"W05.xaml","identicalToEnUS":false},{"culture":"th-TH","error":"boom"}]"#
        let p = try GoldXamlFamily.invarianceProblems(Data(json.utf8))
        #expect(p == ["th-TH: W05.xaml differs from en-US", "th-TH: the recipes threw — boom"])
    }
}
