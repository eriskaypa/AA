// Golden-fixture plan, Swift side (spec 01 GF.8.1, DATA-306/307/311): locates the fixture tree, decodes the
// MANIFEST.json written by the C# oracles (mac/Tools/WinFixtures, WinCapture, XlsxGolden) and exposes the case
// records to the per-family suites. Absent goldens disable the suites with a clear message unless
// AA_REQUIRE_FIXTURES=1 (CI / release), which turns absence into a failure (GF.8.1, GF.9 item 6).
import Foundation
import Testing
@testable import AACore

// MARK: - Paths

/// The fixture folders this harness reads and writes (GF.4.1, adapted to the SwiftPM layout of ARCH §10.2:
/// `mac/Tests/AACoreTests/Fixtures/…`). Located from `#filePath` so the `mac-out` emitter can write into the source
/// tree; falls back to the copied test-bundle resources when the source tree is not reachable.
enum GoldPaths {
    /// `mac/Tests/AACoreTests/Fixtures` in the source tree (or the bundle copy).
    static let fixturesRoot: URL = {
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()            // WinFixtures/
            .deletingLastPathComponent()            // AACoreTests/
            .appending(path: "Fixtures", directoryHint: .isDirectory)
        if FileManager.default.fileExists(atPath: source.path) { return source }
        return Fixtures.root
    }()

    /// True when `fixturesRoot` is the source tree (writable by the emitters), not the bundle copy.
    static var isSourceTree: Bool { !fixturesRoot.path.contains(".xctest/") && !fixturesRoot.path.contains(".bundle/") }

    static var winfixtures: URL { fixturesRoot.appending(path: "winfixtures", directoryHint: .isDirectory) }
    static var winfixturesInputs: URL { winfixtures.appending(path: "inputs", directoryHint: .isDirectory) }
    static var xlsxGoldens: URL { winfixtures.appending(path: "xlsx", directoryHint: .isDirectory) }
    static var xlsxInputs: URL { winfixtures.appending(path: "xlsx-inputs", directoryHint: .isDirectory) }
    static var wpfCapture: URL { fixturesRoot.appending(path: "xaml/wpf-capture", directoryHint: .isDirectory) }
    static var macRoundtrip: URL { fixturesRoot.appending(path: "xaml/mac-roundtrip", directoryHint: .isDirectory) }
    static var macOut: URL { fixturesRoot.appending(path: "mac-out", directoryHint: .isDirectory) }
    /// F2's XLSX fixtures (copies of the POC workbooks) — read-only input of the XlsxGolden comparison (10 X.7.6).
    static var f2Xlsx: URL { fixturesRoot.appending(path: "xlsx", directoryHint: .isDirectory) }
}

// MARK: - Environment switches (GF.8.1, GF.8.5, GF.8.6)

enum GoldEnv {
    /// `AA_REQUIRE_FIXTURES=1`: absence of goldens is a failure, not a skip.
    static var requireFixtures: Bool { ProcessInfo.processInfo.environment["AA_REQUIRE_FIXTURES"] == "1" }
    /// `AA_EMIT_MAC_OUT=1`: the reverse-direction emitter writes `Fixtures/mac-out/` (DATA-312).
    static var emitMacOut: Bool { ProcessInfo.processInfo.environment["AA_EMIT_MAC_OUT"] == "1" }
    /// `AA_EMIT_XLSX_INPUTS=1`: writes the synthetic 10 X.8 workbooks for the XlsxGolden oracle.
    static var emitXlsxInputs: Bool { ProcessInfo.processInfo.environment["AA_EMIT_XLSX_INPUTS"] == "1" }
    /// `AA_REAL_DATA_JSON=<path>`: the optional local-only round trip of a real file (DATA-314).
    static var realDataJSON: String? {
        let v = ProcessInfo.processInfo.environment["AA_REAL_DATA_JSON"]
        return (v?.isEmpty ?? true) ? nil : v
    }
}

// MARK: - Tags (GF.8.6; prefixed per ARCH §12.2)

extension Tag {
    /// Every golden-fixture test.
    @Tag static var goldWinFixtures: Self
    /// `should`-level cases: reported, not release-blocking.
    @Tag static var goldShould: Self
}

// MARK: - Manifest model (GF.4.3, GF.4.4)

/// One output file of a case (`outputs[]` of GF.4.4). `compare` may override the case's mode for this output
/// (e.g. a settings case records the file bytes `bytes-masked` and the state dump `json-semantic`).
struct GoldOutputRef: Sendable, Hashable, CustomStringConvertible {
    var role: String
    var file: String
    var pointer: String?
    var compare: GoldCompareMode?

    var description: String { "\(role) → \(file)\(pointer.map { "#\($0)" } ?? "")" }
}

/// GF.4.4 `macExpectation`.
struct GoldMacExpectation: Sendable, Hashable {
    enum Kind: String, Sendable { case same, divergent }
    var kind: Kind
    /// The Mac-expected golden (divergent only).
    var file: String?
    /// The output role the Mac-expected file replaces (default: the case's first output).
    var role: String?
    /// The spec clause that mandates the divergence (GF.9 item 8).
    var reason: String?
    var compare: GoldCompareMode?

    static let same = GoldMacExpectation(kind: .same)
}

/// GF.4.9 comparison modes.
enum GoldCompareMode: String, Sendable, CaseIterable {
    case bytes
    case bytesMasked = "bytes-masked"
    case jsonSemantic = "json-semantic"
    case zipManifest = "zip-manifest"
    case zipManifestOrdered = "zip-manifest-ordered"
    case textLF = "text-lf"
    case xmlCanonical = "xml-canonical"
    case recordOnly = "record-only"
}

/// GF.4.4 `normative`.
enum GoldNormative: String, Sendable { case must, should, recordOnly = "record-only" }

/// GF.4.4 `platform`.
enum GoldPlatform: String, Sendable { case any, unix, windows }

/// One case record of `MANIFEST.json` (GF.4.4). `CustomTestStringConvertible` = the case id, so parameterised
/// tests show `A13.4` rather than a struct dump.
struct GoldFixtureCase: Sendable, Hashable, CustomTestStringConvertible, CustomStringConvertible {
    var id: String
    var family: String
    var title: String
    var platform: GoldPlatform
    var tz: String?
    var normative: GoldNormative
    var compare: GoldCompareMode
    var dependsOnToday: Bool
    var today: String?
    var inputs: JSONObject
    var outputs: [GoldOutputRef]
    var macExpectation: GoldMacExpectation
    var settles: [String]

    var testDescription: String { id }
    var description: String { "\(id) — \(title)" }

    /// `A06.3` → `A06`; `E01.14` → `E01`; `W01b-S1-typed` → `W01`; `M-01` → `M-01`.
    var group: String {
        if let dot = id.firstIndex(of: ".") { return String(id[..<dot]) }
        if id.count >= 3, let f = id.first, f.isLetter, id.dropFirst().prefix(2).allSatisfy(\.isNumber) {
            return String(id.prefix(3))
        }
        return id
    }

    func output(_ role: String) -> GoldOutputRef? { outputs.first { $0.role == role } }
    func input(_ key: String) -> JSONValue? { inputs[key] }
    func inputString(_ key: String) -> String? { inputs[key]?.stringValue }
}

/// A `specConflicts[]` entry (DATA-308).
struct GoldSpecConflict: Sendable, Hashable {
    var caseID: String
    var spec: String
    var literal: String
    var golden: String
    var note: String
    var erratum: String?
}

/// `MANIFEST.json` (GF.4.3).
struct GoldManifest: Sendable {
    var schema: Int
    var generatorName: String
    var generatorVersion: String
    var linkedSourcesCommit: String?
    var linkedSources: [(path: String, sha256: String)]
    var generatedAtUtc: String?
    var today: String?
    var runs: [JSONObject]
    var cases: [GoldFixtureCase]
    var specConflicts: [GoldSpecConflict]
    var platformDivergences: [JSONObject]

    enum DecodeError: Error, CustomStringConvertible {
        case notAnObject, missing(String), invalid(String, String)
        var description: String {
            switch self {
            case .notAnObject: return "MANIFEST.json is not a JSON object"
            case .missing(let k): return "MANIFEST.json: missing \"\(k)\""
            case .invalid(let k, let why): return "MANIFEST.json: invalid \"\(k)\" (\(why))"
            }
        }
    }

    init(data: Data) throws {
        let root = try JSONParser.parse(data)
        try self.init(json: root)
    }

    init(json root: JSONValue) throws {
        guard let o = root.objectValue else { throw DecodeError.notAnObject }
        guard let schema = o["schema"]?.numberValue?.intValue else { throw DecodeError.missing("schema") }
        guard schema == 1 else { throw DecodeError.invalid("schema", "only schema 1 is understood, got \(schema)") }
        self.schema = schema
        let gen = o["generator"]?.objectValue ?? JSONObject()
        generatorName = gen["name"]?.stringValue ?? ""
        generatorVersion = gen["version"]?.stringValue ?? ""
        linkedSourcesCommit = gen["linkedSourcesCommit"]?.stringValue
        linkedSources = (gen["linkedSources"]?.arrayValue ?? []).compactMap { v in
            guard let e = v.objectValue, let p = e["path"]?.stringValue, let h = e["sha256"]?.stringValue else { return nil }
            return (p, h)
        }
        generatedAtUtc = o["generatedAtUtc"]?.stringValue
        today = o["today"]?.stringValue
        runs = (o["runs"]?.arrayValue ?? []).compactMap(\.objectValue)
        guard let rawCases = o["cases"]?.arrayValue else { throw DecodeError.missing("cases") }
        var seen = Set<String>()
        cases = try rawCases.map { v in
            let c = try GoldManifest.decodeCase(v)
            guard seen.insert(c.id).inserted else { throw DecodeError.invalid("cases", "duplicate id \(c.id)") }
            return c
        }
        specConflicts = (o["specConflicts"]?.arrayValue ?? []).compactMap { v in
            guard let e = v.objectValue else { return nil }
            return GoldSpecConflict(caseID: e["case"]?.stringValue ?? "", spec: e["spec"]?.stringValue ?? "",
                                    literal: e["literal"]?.stringValue ?? "", golden: e["golden"]?.stringValue ?? "",
                                    note: e["note"]?.stringValue ?? "", erratum: e["erratum"]?.stringValue)
        }
        platformDivergences = (o["platformDivergences"]?.arrayValue ?? []).compactMap(\.objectValue)
    }

    static func decodeCase(_ v: JSONValue) throws -> GoldFixtureCase {
        guard let o = v.objectValue else { throw DecodeError.invalid("cases", "a case is not an object") }
        guard let id = o["id"]?.stringValue, !id.isEmpty else { throw DecodeError.missing("cases[].id") }
        func mode(_ s: String?, _ key: String) throws -> GoldCompareMode? {
            guard let s else { return nil }
            guard let m = GoldCompareMode(rawValue: s) else { throw DecodeError.invalid("\(id).\(key)", "unknown mode \(s)") }
            return m
        }
        let compare = try mode(o["compare"]?.stringValue, "compare") ?? .bytesMasked
        let platformText = o["platform"]?.stringValue ?? "any"
        guard let platform = GoldPlatform(rawValue: platformText) else {
            throw DecodeError.invalid("\(id).platform", platformText)
        }
        let normText = o["normative"]?.stringValue ?? "must"
        guard let normative = GoldNormative(rawValue: normText) else {
            throw DecodeError.invalid("\(id).normative", normText)
        }
        var outputs: [GoldOutputRef] = []
        for ov in o["outputs"]?.arrayValue ?? [] {
            guard let oo = ov.objectValue, let file = oo["file"]?.stringValue else {
                throw DecodeError.invalid("\(id).outputs", "an output needs a file")
            }
            outputs.append(GoldOutputRef(role: oo["role"]?.stringValue ?? "result", file: file,
                                         pointer: oo["pointer"]?.stringValue,
                                         compare: try mode(oo["compare"]?.stringValue, "outputs.compare")))
        }
        var mac = GoldMacExpectation.same
        if let m = o["macExpectation"]?.objectValue {
            let kindText = m["kind"]?.stringValue ?? "same"
            guard let kind = GoldMacExpectation.Kind(rawValue: kindText) else {
                throw DecodeError.invalid("\(id).macExpectation.kind", kindText)
            }
            mac = GoldMacExpectation(kind: kind, file: m["file"]?.stringValue, role: m["role"]?.stringValue,
                                     reason: m["reason"]?.stringValue,
                                     compare: try mode(m["compare"]?.stringValue, "macExpectation.compare"))
            if kind == .divergent && (mac.reason ?? "").isEmpty {
                throw DecodeError.invalid("\(id).macExpectation", "a divergent expectation must cite its spec clause (GF.9 item 8)")
            }
        }
        return GoldFixtureCase(
            id: id, family: o["family"]?.stringValue ?? "", title: o["title"]?.stringValue ?? "",
            platform: platform, tz: o["tz"]?.stringValue, normative: normative, compare: compare,
            dependsOnToday: o["dependsOnToday"]?.boolValue ?? false, today: o["today"]?.stringValue,
            inputs: o["inputs"]?.objectValue ?? JSONObject(), outputs: outputs, macExpectation: mac,
            settles: (o["settles"]?.arrayValue ?? []).compactMap(\.stringValue))
    }
}

// MARK: - Index

/// A fixture root and its decoded manifest. `available` is false when `MANIFEST.json` is absent; a present but
/// undecodable manifest is reported through `loadError` (and fails the presence test) rather than silently skipping.
struct GoldFixtureIndex: Sendable {
    let root: URL
    let manifest: GoldManifest?
    let loadError: String?

    var available: Bool { manifest != nil }
    var manifestURL: URL { root.appending(path: "MANIFEST.json") }

    init(root: URL) {
        self.root = root
        let url = root.appending(path: "MANIFEST.json")
        guard let data = try? Data(contentsOf: url) else { manifest = nil; loadError = nil; return }
        do { manifest = try GoldManifest(data: data); loadError = nil } catch {
            manifest = nil; loadError = String(describing: error)
        }
    }

    init(root: URL, manifest: GoldManifest) {
        self.root = root; self.manifest = manifest; loadError = nil
    }

    /// Part 1 goldens (`Fixtures/winfixtures/`).
    static let winfixtures = GoldFixtureIndex(root: GoldPaths.winfixtures)
    /// Part 2 WPF captures (`Fixtures/xaml/wpf-capture/`).
    static let wpfCapture = GoldFixtureIndex(root: GoldPaths.wpfCapture)

    /// Cases of one family (`json`, `settings`, `bundles`, `crypto`, `services`, `ext`, `xaml`), sorted by id
    /// ordinally — the order the generator writes them.
    func cases(family: String) -> [GoldFixtureCase] {
        (manifest?.cases ?? []).filter { $0.family == family }
            .sorted { Ordinal.compare($0.id, $1.id) == .orderedAscending }
    }

    /// The `platform: windows` twin of a case (DATA-310: the Windows run records its cases with a `w` suffix,
    /// e.g. `A25w`, written under `windows/`). The Mac expectation for Windows-form inputs is that run.
    func windowsTwin(of c: GoldFixtureCase) -> GoldFixtureCase? {
        manifest?.cases.first { $0.id == c.id + "w" && $0.platform == .windows }
    }

    func url(_ relative: String) -> URL { root.appending(path: relative) }
    func data(_ relative: String) throws -> Data { try Data(contentsOf: url(relative)) }
    func exists(_ relative: String) -> Bool { FileManager.default.fileExists(atPath: url(relative).path) }

    /// The clear skip message every golden suite shows when the goldens are absent (GF.8.1).
    static let absentMessage: Comment =
        "Windows goldens are absent: run `Scripts/fixtures.sh generate` with the .NET 10 SDK (mac/Tools/WinFixtures/README.md) and commit Tests/AACoreTests/Fixtures/winfixtures/; set AA_REQUIRE_FIXTURES=1 to make absence fail"
    static let absentCaptureMessage: Comment =
        "WPF captures are absent: run WinCapture on Windows (mac/Tools/WinCapture/README.md) and commit Tests/AACoreTests/Fixtures/xaml/wpf-capture/"
}

// MARK: - Presence gate

/// GF.8.1 / GF.9 item 6: with `AA_REQUIRE_FIXTURES=1` the absence (or an undecodable manifest) is a failure;
/// otherwise this suite only reports what it found.
@Suite("WinFixtures presence", .tags(.goldWinFixtures))
struct GoldFixturePresenceTests {
    @Test("Part 1 goldens present when required; manifest decodes when present")
    func winfixturesPresence() {
        let index = GoldFixtureIndex.winfixtures
        if let err = index.loadError { Issue.record("Fixtures/winfixtures/MANIFEST.json is present but unreadable: \(err)") }
        if GoldEnv.requireFixtures && !index.available && index.loadError == nil {
            Issue.record("AA_REQUIRE_FIXTURES=1 but \(index.manifestURL.path) is absent")
        }
    }

    @Test("Part 2 captures present when required; manifest decodes when present")
    func wpfCapturePresence() {
        let index = GoldFixtureIndex.wpfCapture
        if let err = index.loadError { Issue.record("Fixtures/xaml/wpf-capture/MANIFEST.json is present but unreadable: \(err)") }
        if GoldEnv.requireFixtures && !index.available && index.loadError == nil {
            Issue.record("AA_REQUIRE_FIXTURES=1 but \(index.manifestURL.path) is absent")
        }
    }

    @Test("Spec conflicts and platform divergences are resolved (GF.9 items 4–5)",
          .enabled(if: GoldFixtureIndex.winfixtures.available, GoldFixtureIndex.absentMessage))
    func conflictsResolved() throws {
        let m = try #require(GoldFixtureIndex.winfixtures.manifest)
        for c in m.specConflicts where (c.erratum ?? "").isEmpty {
            Issue.record("spec conflict without an erratum: case \(c.caseID), \(c.spec): literal \(c.literal) vs golden \(c.golden) — \(c.note)")
        }
        for d in m.platformDivergences where (d["resolution"]?.stringValue ?? "").isEmpty {
            Issue.record("unresolved platform divergence: \((try? JSONWriter.string(.object(d))) ?? "?")")
        }
    }
}
