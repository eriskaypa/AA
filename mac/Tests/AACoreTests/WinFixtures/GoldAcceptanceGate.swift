// The acceptance gate of the golden-fixture plan (spec 01 GF.9, DATA-326), as far as the Swift side can check it:
//
//   item 1  the committed manifest's provenance names the pinned commit, and every linked source it records carries
//           the hash of mac/Docs/original-source-checksums.sha256
//   item 3  every GF.1.1 ledger row points at a case present in a committed manifest (Part 1 and Part 2)
//   item 6  with AA_REQUIRE_FIXTURES=1 every fixture source is present (Part 1, Part 2, the manual confirmations,
//           the W23 load-check and the XlsxGolden output) — absence is a failure, not a skip
//   item 9  no file outside mac/ changed: the read-only Windows sources still hash to their pins
//
// Items 2 (two generate runs byte-identical) and 7 (check-mac / load-check exit codes) are properties of the C# runs
// (`generate --verify-only`, `check-mac`, `WinCapture load-check`); items 4, 5 and 8 are asserted by
// GoldFixturePresenceTests and the manifest decoder.
import CryptoKit
import Foundation
import Testing
@testable import AACore

enum GoldAcceptance {
    /// The commit the linked sources are pinned at (01 GF.0 §0, `SourcePin.PinnedCommit` in the oracle).
    static let pinnedCommit = "37cdab0"

    /// The repository root (`mac/..`), located from this file.
    static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()            // WinFixtures/
            .deletingLastPathComponent()            // AACoreTests/
            .deletingLastPathComponent()            // Tests/
            .deletingLastPathComponent()            // mac/
            .deletingLastPathComponent()
    }

    static var checksumFile: URL { repoRoot.appending(path: "mac/Docs/original-source-checksums.sha256") }

    /// `<hex>␠␠<path>` lines → path → hex.
    static func pins(_ text: String) -> [String: String] {
        var out: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            let s = String(line)
            guard s.count > 66, s.dropFirst(64).hasPrefix("  ") else { continue }
            out[String(s.dropFirst(66))] = String(s.prefix(64)).lowercased()
        }
        return out
    }

    // MARK: Ledger (GF.1.1)

    /// Where a ledger reference must be found.
    enum Ref: Sendable, CustomStringConvertible {
        /// A case id (or id prefix: `A12` covers `A12.1…A12.12`) of the WinFixtures manifest.
        case part1(String)
        /// A capture id prefix of the WinCapture manifest (`W01` covers `W01a-pristine`, `W01b-S1-typed`, …).
        case wpf(String)
        /// A file of `xaml/wpf-capture/manual/`.
        case manual(String)
        /// `xaml/mac-roundtrip/load-check.json` (W23).
        case loadCheck

        var description: String {
            switch self {
            case .part1(let id): return "WinFixtures case \(id)"
            case .wpf(let id): return "WinCapture capture \(id)"
            case .manual(let f): return "manual/\(f)"
            case .loadCheck: return "xaml/mac-roundtrip/load-check.json (W23)"
            }
        }
    }

    struct Row: Sendable {
        var marker: String
        var refs: [Ref]
    }

    /// GF.1.1, row by row (W19 and the windows run of A25 are the `w`-suffixed windows twins, Deviations GOLD-N5/N6).
    static let ledger: [Row] = [
        Row(marker: "01:1438 §4.1.3 Verification TODO", refs: [.part1("A02"), .part1("A03"), .part1("A04"), .part1("A23")]),
        Row(marker: "01 §8.2 Q-2", refs: [.part1("A02")]),
        Row(marker: "01 §7.4 depth off-by-one", refs: [.part1("A18")]),
        Row(marker: "01 §7.14-1 Required before release", refs: [.part1("A02"), .part1("A03")]),
        Row(marker: "01 §3.15 hash-set order / unstable sort", refs: [.part1("E01.14"), .part1("E01.15"), .part1("E01.16")]),
        Row(marker: "01 §4.1.5 ambiguous/invalid local times", refs: [.part1("A12"), .part1("A13")]),
        Row(marker: "01 §4.1.7 JavaScriptEncoder escaping", refs: [.part1("A09")]),
        Row(marker: "01 §7.2 enc: vectors computed with Python", refs: [.part1("K03"), .part1("K04")]),
        Row(marker: "04:931 Windows-written property order", refs: [.part1("A02")]),
        Row(marker: "04:1018 lock hashes across platforms", refs: [.part1("K08"), .part1("K09")]),
        Row(marker: "02 §7.2 T-DONE-12 / D-21", refs: [.part1("A16")]),
        Row(marker: "05 §7.6 test1234 vector", refs: [.part1("K03")]),
        Row(marker: "06 §7.14 template order, dangling GroupId, +02:00", refs: [.part1("A02"), .part1("A14")]),
        Row(marker: "09 §7.1 ParseDate — verify", refs: [.part1("E10")]),
        Row(marker: "09 §7.2 DateResolver — verify", refs: [.part1("E09")]),
        Row(marker: "10:1637 TwoDigitYearMax", refs: [.part1("E10")]),
        Row(marker: "11 §4.5, 09 §7.13 XLSX part bytes", refs: [.part1("E13"), .part1("E14"), .manual("M-07.checklist.xlsx")]),
        Row(marker: "05 §4.3.4 S-1, 03 Q-9, 03:1221 root attribute set", refs: [.wpf("W01"), .manual("M-01.xaml")]),
        Row(marker: "05 S-4 Table.Columns / BorderThickness", refs: [.wpf("W02"), .manual("M-02.xaml")]),
        Row(marker: "05 S-5 Hyperlink default style", refs: [.wpf("W03"), .manual("M-03.xaml")]),
        Row(marker: "05 S-9 Typography.Variants", refs: [.wpf("W04"), .manual("M-04.xaml")]),
        Row(marker: "05 S-10, 05 §9 Q6 empty document", refs: [.wpf("W05"), .manual("M-05.xaml")]),
        Row(marker: "05 CONT-030 built-in key map", refs: [.wpf("W06")]),
        Row(marker: "05 CONT-023, 05:566 toggles, strike comparison", refs: [.wpf("W07")]),
        Row(marker: "05 CONT-040/041/043/044 lists", refs: [.wpf("W08")]),
        Row(marker: "05 S-2/S-3 normalised list shapes", refs: [.wpf("W09")]),
        Row(marker: "05 CONT-011, D-2 undo after load", refs: [.wpf("W10")]),
        Row(marker: "05 §9 Q1 RTF/Word paste shapes", refs: [.wpf("W11")]),
        Row(marker: "05 §7.1 exact Windows HTML output", refs: [.wpf("W12")]),
        Row(marker: "05 §9 Q1 combined decorations", refs: [.wpf("W13")]),
        Row(marker: "05 CONT-038 embedded-image placeholder", refs: [.wpf("W14")]),
        Row(marker: "05 §4.3.1 contextual properties", refs: [.wpf("W15")]),
        Row(marker: "12 Q-1 SIRE golden XAML", refs: [.wpf("W16")]),
        Row(marker: "05 §4.4 lock sentinel round trip", refs: [.wpf("W17")]),
        Row(marker: "05 CONT-028 Clear formatting", refs: [.wpf("W18")]),
        Row(marker: "05 §7.7-10 Windows loads every Mac XAML", refs: [.loadCheck]),
        Row(marker: "01 §4.6, §7.3 real AAENC1 / AADPAPI1 files", refs: [.part1("W19w")]),
        Row(marker: "01 §3.7 [MAC], §7.6 Windows Path semantics", refs: [.part1("A25xw")]),
    ]

    /// What is committed, per source (nil = that source is absent, so its references cannot be checked yet).
    struct Sources: Sendable {
        var part1: [String]?
        var wpf: [String]?
        var manual: Set<String>?
        var loadCheck: Bool?
    }

    static func found(_ ref: Ref, in s: Sources) -> Bool? {
        switch ref {
        case .part1(let p): return s.part1.map { ids in ids.contains { $0 == p || $0.hasPrefix(p) } }
        case .wpf(let p): return s.wpf.map { ids in ids.contains { $0.hasPrefix(p) } }
        case .manual(let f): return s.manual.map { $0.contains(f) }
        case .loadCheck: return s.loadCheck
        }
    }

    /// Ledger rows with a reference that is not committed. With `require`, a reference into an absent source is
    /// missing too; otherwise it is skipped (the source's own suite reports the absence).
    static func ledgerProblems(_ s: Sources, require: Bool) -> [String] {
        var out: [String] = []
        for row in ledger {
            for ref in row.refs {
                switch found(ref, in: s) {
                case .some(true): continue
                case .some(false): out.append("GF.1.1 \(row.marker): \(ref) is not in the committed fixtures")
                case .none where require: out.append("GF.1.1 \(row.marker): \(ref) cannot be checked — its fixture source is absent")
                case .none: continue
                }
            }
        }
        return out
    }

    static var committedSources: Sources {
        let manualFiles: Set<String>? = GoldManualCaptures.available
            ? Set((try? FileManager.default.contentsOfDirectory(atPath: GoldManualCaptures.manualDir.path)) ?? [])
            : nil
        return Sources(part1: GoldFixtureIndex.winfixtures.manifest?.cases.map(\.id),
                       wpf: GoldFixtureIndex.wpfCapture.manifest?.cases.map(\.id),
                       manual: manualFiles,
                       loadCheck: GoldMacRoundtrip.available ? true : nil)
    }

    // MARK: Provenance (item 1)

    static func provenanceProblems(_ m: GoldManifest, pins: [String: String]) -> [String] {
        var out: [String] = []
        // `git log --format=%h` may print a longer abbreviation than the pin: equal when one is a prefix of the other.
        let commit = m.linkedSourcesCommit ?? ""
        if commit.count < 7 || !(commit.hasPrefix(pinnedCommit) || pinnedCommit.hasPrefix(commit)) {
            out.append("MANIFEST.generator.linkedSourcesCommit is \(m.linkedSourcesCommit ?? "absent"), not the pinned \(pinnedCommit)")
        }
        if m.linkedSources.isEmpty { out.append("MANIFEST.generator.linkedSources is empty (DATA-301 provenance)") }
        for s in m.linkedSources {
            guard let pin = pins[s.path] else { out.append("\(s.path) is linked but not pinned in original-source-checksums.sha256"); continue }
            if pin != s.sha256.lowercased() { out.append("\(s.path): generated from \(s.sha256), pinned \(pin)") }
        }
        return out
    }

    // MARK: Source pins (item 9)

    /// Files under the repository root whose SHA-256 differs from its pin (or that are missing).
    static func pinProblems(root: URL, pins: [String: String]) -> [String] {
        var out: [String] = []
        for (path, hex) in pins.sorted(by: { $0.key < $1.key }) {
            guard let data = try? Data(contentsOf: root.appending(path: path)) else { out.append("\(path): missing"); continue }
            let actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            if actual != hex { out.append("\(path): sha256 \(actual) ≠ pinned \(hex) — a read-only Windows source changed (rule zero)") }
        }
        return out
    }
}

@Suite("WinFixtures — acceptance gate (DATA-326, GF.9)", .tags(.goldWinFixtures))
struct GoldAcceptanceGateTests {
    @Test("item 9: the read-only Windows sources still hash to their pins (no file outside mac/ changed)",
          .enabled(if: FileManager.default.fileExists(atPath: GoldAcceptance.repoRoot.appending(path: "AA").path),
                   "the Windows sources (AA/) are not in this checkout"))
    func sourcesPinned() throws {
        let pins = GoldAcceptance.pins(String(decoding: try Data(contentsOf: GoldAcceptance.checksumFile), as: UTF8.self))
        #expect(pins.count > 100, "original-source-checksums.sha256 lists only \(pins.count) files")
        for p in GoldAcceptance.pinProblems(root: GoldAcceptance.repoRoot, pins: pins) { Issue.record(Comment(rawValue: p)) }
    }

    @Test("item 1: the manifest's provenance is the pinned commit and the pinned hashes",
          .enabled(if: GoldFixtureIndex.winfixtures.available, GoldFixtureIndex.absentMessage))
    func provenance() throws {
        let m = try #require(GoldFixtureIndex.winfixtures.manifest)
        let pins = GoldAcceptance.pins(String(decoding: try Data(contentsOf: GoldAcceptance.checksumFile), as: UTF8.self))
        for p in GoldAcceptance.provenanceProblems(m, pins: pins) { Issue.record(Comment(rawValue: p)) }
    }

    @Test("item 3: every GF.1.1 ledger row points at a committed case (references into absent sources wait)")
    func ledger() {
        for p in GoldAcceptance.ledgerProblems(GoldAcceptance.committedSources, require: GoldEnv.requireFixtures) {
            Issue.record(Comment(rawValue: p))
        }
    }

    @Test("item 6: with AA_REQUIRE_FIXTURES=1 every fixture source is present",
          .enabled(if: GoldEnv.requireFixtures, "set AA_REQUIRE_FIXTURES=1 (release gate) to make absence fail"))
    func everySourcePresent() {
        if !GoldManualCaptures.available { Issue.record("Fixtures/xaml/wpf-capture/manual/ is absent (DATA-323, GF.6.7)") }
        if !GoldMacRoundtrip.available { Issue.record("Fixtures/xaml/mac-roundtrip/load-check.json is absent (DATA-325, W23)") }
        if !GoldXlsxInputs.available { Issue.record("Fixtures/winfixtures/xlsx/ goldens are absent (10 X.7.6, XlsxGolden)") }
        if !FileManager.default.fileExists(atPath: GoldPaths.wpfCapture.appending(path: "inputs").path) {
            Issue.record("Fixtures/xaml/wpf-capture/inputs/ (clipboard captures) is absent (DATA-322, GF.6.6)")
        }
    }
}

@Suite("WinFixtures harness — acceptance-gate logic (GF.9)", .tags(.goldWinFixtures))
struct GoldAcceptanceHarnessTests {
    @Test("checksum lines parse; a changed or missing file is reported")
    func pins() throws {
        let folder = TempFolder("gold-pins")
        try folder.write("AA/a.cs", "class A {}\n")
        let good = SHA256.hash(data: Data("class A {}\n".utf8)).map { String(format: "%02x", $0) }.joined()
        let text = "\(good)  AA/a.cs\n\(String(repeating: "0", count: 64))  AA/b.cs\nnot a line\n"
        let pins = GoldAcceptance.pins(text)
        #expect(pins == ["AA/a.cs": good, "AA/b.cs": String(repeating: "0", count: 64)])
        #expect(GoldAcceptance.pinProblems(root: folder.url, pins: pins) == ["AA/b.cs: missing"])
        try folder.write("AA/a.cs", "class A { }\n")
        #expect(GoldAcceptance.pinProblems(root: folder.url, pins: ["AA/a.cs": good]).first?.contains("rule zero") == true)
    }

    @Test("provenance: wrong commit, unpinned path and hash mismatch are reported")
    func provenance() throws {
        let text = #"{"schema":1,"generator":{"linkedSourcesCommit":"abc1234","linkedSources":[{"path":"AA/Models/Models.cs","sha256":"AB"},{"path":"AA/X.cs","sha256":"00"}]},"cases":[]}"#
        let m = try GoldManifest(data: Data(text.utf8))
        let p = GoldAcceptance.provenanceProblems(m, pins: ["AA/Models/Models.cs": "ab"])
        #expect(p.count == 2)
        #expect(p[0].contains("abc1234"))
        #expect(p[1].contains("AA/X.cs is linked but not pinned"))
        let bad = GoldAcceptance.provenanceProblems(m, pins: ["AA/Models/Models.cs": "cd", "AA/X.cs": "00"])
        #expect(bad.contains { $0.hasPrefix("AA/Models/Models.cs: generated from AB") })
        let longer = try GoldManifest(data: Data(#"{"schema":1,"generator":{"linkedSourcesCommit":"37cdab0f1","linkedSources":[{"path":"AA/X.cs","sha256":"00"}]},"cases":[]}"#.utf8))
        #expect(GoldAcceptance.provenanceProblems(longer, pins: ["AA/X.cs": "00"]).isEmpty)
    }

    @Test("ledger: every row resolves against a complete synthetic catalogue; gaps and absent sources are reported")
    func ledger() {
        let part1 = ["A02", "A03", "A04", "A09a", "A09b", "A12.1", "A13.1", "A14.1", "A16.1", "A18", "A23", "A25xw",
                     "E01.14", "E01.15", "E01.16", "E09", "E10.1", "E13.X1", "E14.1", "K03", "K04", "K08", "K09", "W19w"]
        let wpf = (1...18).map { String(format: "W%02d", $0) + "x-capture" }
        let manual: Set<String> = ["M-01.xaml", "M-02.xaml", "M-03.xaml", "M-04.xaml", "M-05.xaml", "M-07.checklist.xlsx"]
        let full = GoldAcceptance.Sources(part1: part1, wpf: wpf, manual: manual, loadCheck: true)
        #expect(GoldAcceptance.ledgerProblems(full, require: true).isEmpty, "\(GoldAcceptance.ledgerProblems(full, require: true))")

        var gap = full
        gap.part1 = part1.filter { $0 != "A18" }
        #expect(GoldAcceptance.ledgerProblems(gap, require: false) == ["GF.1.1 01 §7.4 depth off-by-one: WinFixtures case A18 is not in the committed fixtures"])

        let none = GoldAcceptance.Sources(part1: nil, wpf: nil, manual: nil, loadCheck: nil)
        #expect(GoldAcceptance.ledgerProblems(none, require: false).isEmpty)
        let required = GoldAcceptance.ledgerProblems(none, require: true)
        #expect(required.count == GoldAcceptance.ledger.reduce(0) { $0 + $1.refs.count })
        #expect(required.allSatisfy { $0.contains("cannot be checked") })
    }
}
