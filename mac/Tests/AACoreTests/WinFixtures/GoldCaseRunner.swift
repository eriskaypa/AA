// The per-case driver shared by every golden suite (spec 01 GF.8, DATA-307/308/309/311): builds the case context
// (fresh data folder, time zone, injected "today"), runs the family's Swift reproducer, loads each golden output,
// compares it by its GF.4.9 mode, applies the Mac expectation (`same` / `divergent`), and reports by normative level
// — `must` fails the test, `should` is a known (non-blocking) issue, `record-only` only attaches the diff.
import Foundation
import Testing
@testable import AACore

// MARK: - Values a reproducer returns

/// One reproduced output.
enum GoldValue: Sendable {
    /// Bytes compared by `bytes`, `bytes-masked`, `text-lf` or `xml-canonical`.
    case bytes(Data)
    /// A JSON value compared `json-semantic` (expectation shapes of GF.4.7).
    case json(JSONValue)
    /// A whole ZIP archive compared `zip-manifest` / `zip-manifest-ordered` (+ its payloads).
    case zip(Data)
    /// The reproducer deliberately does not reproduce this output (e.g. a .NET exception message); the reason is
    /// shown in the report.
    case skip(String)

    static func text(_ s: String) -> GoldValue { .bytes(Data(s.utf8)) }
}

typealias GoldActual = [String: GoldValue]

/// Everything a reproducer needs. One per case run; the data folder is deleted afterwards.
@MainActor
final class GoldCaseContext {
    let index: GoldFixtureIndex
    let fixtureCase: GoldFixtureCase
    let folder: TempFolder
    let zone: TimeZone
    let today: CivilDate
    let bindings = GoldBindings()
    let startedAt = Date()

    init(index: GoldFixtureIndex, fixtureCase: GoldFixtureCase) {
        self.index = index
        self.fixtureCase = fixtureCase
        folder = TempFolder("aa-gold-\(fixtureCase.id)")
        zone = fixtureCase.tz.flatMap(TimeZone.init(identifier:)) ?? TimeZone(identifier: "Europe/Athens")!
        today = (fixtureCase.today ?? index.manifest?.today).flatMap { CivilDate(iso: $0) }
            ?? CivilDate(year: 2026, month: 9, day: 30)!
    }

    /// The Mac data folder that stands in for `%%DATADIR%%`.
    var dataFolder: URL { folder.url }

    var matchContext: GoldMatchContext { GoldMatchContext(dataDir: dataFolder.path, now: startedAt) }

    /// A `DataStore` over the case's data folder, with an in-memory Keychain and the case's time zone.
    func makeDataStore(clock: AppClock? = nil) -> DataStore {
        let ds = DataStore(appFolder: dataFolder, secrets: InMemorySecretStore(),
                           clock: clock ?? GoldZoneClock(zone: zone))
        ds.loadSettings()
        return ds
    }

    /// A decode context in the case's zone (clock defaults to the case's zone, real time).
    var decodeContext: JSONDecodeContext { JSONDecodeContext(zone: zone, clock: GoldZoneClock(zone: zone)) }

    var encodeOptions: JSONEncodeOptions { JSONEncodeOptions(zone: zone) }

    // Inputs (GF.4.1 `inputs/`) and goldens.

    func inputData(_ name: String) throws -> Data { try index.data("inputs/\(name)") }
    func goldenData(_ relative: String) throws -> Data { try index.data(relative) }
    func inline(_ key: String) -> JSONValue? { fixtureCase.inputs[key] }
    func inlineString(_ key: String) -> String? { fixtureCase.inputs[key]?.stringValue }

    /// The inline input `key` as the text of an AA-format document (inline inputs are stored as JSON strings).
    func inlineDocument(_ key: String = "inline") throws -> Data {
        guard let s = inlineString(key) else { throw GoldReproError.missingInput(key) }
        return Data(s.utf8)
    }
}

/// A clock that reports real time but in a fixed zone (the case's tz), so `Added = Now` defaults are Local in that
/// zone exactly like the .NET child process running with `TZ=<zone>`.
struct GoldZoneClock: AppClock {
    let timeZone: TimeZone
    init(zone: TimeZone) { timeZone = zone }
    func instant() -> Date { Date() }
    func now() -> NetDateTime { NetDateTime(date: instant(), kind: .local, zone: timeZone) }
    func utcNow() -> NetDateTime { NetDateTime(date: instant(), kind: .utc, zone: timeZone) }
    func today() -> CivilDate { now().civilDate }
}

enum GoldReproError: Error, CustomStringConvertible {
    case missingInput(String)
    case unexpected(String)
    var description: String {
        switch self {
        case .missingInput(let k): return "the case has no input \"\(k)\""
        case .unexpected(let s): return s
        }
    }
}

// MARK: - Reproducer table

/// A Swift reproduction of one case (or one group of cases: `A06` covers `A06.1…A06.14`).
struct GoldReproducer: Sendable {
    /// When set, the reproducer needs another wave owner's real code; until that owner flips its ContractStatus the
    /// case is reported as pending (a failure only under AA_REQUIRE_FIXTURES=1).
    var requires: ContractOwner?
    /// Set when the Mac API this case needs is private to another owner (ARCH §6.8 last paragraph): the case is
    /// pending until a reproducer is written against it (Docs/Requests/W-GOLD.md names each one).
    var pendingNote: String?
    var run: @MainActor @Sendable (GoldCaseContext) async throws -> GoldActual

    init(requires: ContractOwner? = nil, _ run: @escaping @MainActor @Sendable (GoldCaseContext) async throws -> GoldActual) {
        self.requires = requires
        self.run = run
    }

    /// A case whose Swift side cannot be written yet (the API is another owner's private code).
    static func pending(_ owner: ContractOwner, _ note: String) -> GoldReproducer {
        var r = GoldReproducer(requires: owner) { _ in [:] }
        r.pendingNote = note
        return r
    }
}

struct GoldReproducerTable: Sendable {
    var entries: [String: GoldReproducer]

    /// Exact id first (`A06.3`), then the group (`A06`), then the family letter + two digits.
    func reproducer(for c: GoldFixtureCase) -> GoldReproducer? {
        if let r = entries[c.id] { return r }
        if c.id.hasSuffix("w"), let r = entries[String(c.id.dropLast())] { return r }
        if let r = entries[c.group] { return r }
        if c.id.count >= 3, let r = entries[String(c.id.prefix(3))] { return r }
        return nil
    }
}

// MARK: - Runner

@MainActor
enum GoldCaseRunner {
    /// Runs one case end to end and records issues according to its normative level.
    static func run(_ c: GoldFixtureCase, index: GoldFixtureIndex, table: GoldReproducerTable) async {
        guard let repro = table.reproducer(for: c) else {
            report(["no Swift reproducer is registered for case \(c.id) (\(c.title)); add one to the family suite"],
                   case: c, attachments: [])
            return
        }
        if let note = repro.pendingNote {
            // A must-case without a Swift side is a visible gap at release (AA_REQUIRE_FIXTURES=1), never silent.
            if GoldEnv.requireFixtures && c.normative == .must {
                Issue.record(Comment(rawValue: "\(c.id): no Swift reproducer yet — \(note)"))
            }
            return
        }
        if let owner = repro.requires, !ContractStatus.isImplemented(owner) {
            if GoldEnv.requireFixtures {
                Issue.record(Comment(rawValue: "\(c.id): the reproducer needs \(owner.rawValue)'s real code (ContractStatus not flipped)"))
            }
            return
        }
        let ctx = GoldCaseContext(index: index, fixtureCase: c)
        let actual: GoldActual
        do {
            actual = try await repro.run(ctx)
        } catch {
            report(["reproducer threw: \(error)"], case: c, attachments: [])
            return
        }
        let outcome = compareAll(c, actual: actual, ctx: ctx)
        report(outcome.problems, case: c, attachments: outcome.attachments)
    }

    struct Outcome {
        var problems: [String] = []
        var attachments: [(name: String, data: Data)] = []
    }

    /// Compares every output (with the Mac expectation applied). Separate from `run` so the harness self-tests can
    /// drive it without the Testing issue machinery.
    static func compareAll(_ c: GoldFixtureCase, actual: GoldActual, ctx: GoldCaseContext) -> Outcome {
        var out = Outcome()
        // What the Mac must reproduce: every Mac-compared output (`same`), or only the Mac-expected golden of the
        // divergent role (`divergent`; the other outputs are the Windows record). A divergence without a Mac golden
        // is asserted by the owner's own tests — nothing to compare here.
        var expectations: [(role: String, file: String, pointer: String?, mode: GoldCompareMode)] = []
        if c.macExpectation.kind == .divergent {
            guard let macFile = c.macExpectation.file else { return out }
            let role = c.macExpectation.role ?? c.outputs.first?.role ?? "result"
            let base = c.outputs.first { $0.role == role }
            expectations.append((role, macFile, c.macExpectation.pointer,
                                 c.macExpectation.compare ?? base?.compare ?? c.compare))
        } else {
            for ref in c.outputs where ref.macCompared {
                expectations.append((ref.role, ref.file, ref.pointer, ref.compare ?? c.compare))
            }
        }
        for e in expectations {
            guard let value = actual[e.role] else {
                out.problems.append("\(e.role): the reproducer produced no output for this role")
                continue
            }
            if case .skip = value { continue }
            let golden: Data
            do { golden = try ctx.goldenData(e.file) } catch {
                out.problems.append("\(e.role): golden \(e.file) is missing from the fixture tree")
                continue
            }
            if let problem = compare(value, golden: golden, pointer: e.pointer, mode: e.mode, goldenFile: e.file, ctx: ctx) {
                out.problems.append("\(e.role) (\(e.file), \(e.mode.rawValue)): \(problem)")
                out.attachments.append((name: "\(c.id).\(e.role).golden", data: goldenBytes(golden, pointer: e.pointer)))
                out.attachments.append((name: "\(c.id).\(e.role).actual", data: actualBytes(value)))
            }
        }
        return out
    }

    /// One output by mode. Returns a human-readable problem or nil.
    static func compare(_ value: GoldValue, golden: Data, pointer: String?, mode: GoldCompareMode, goldenFile: String,
                        ctx: GoldCaseContext) -> String? {
        let mc = ctx.matchContext
        switch mode {
        case .recordOnly:
            return nil
        case .bytes, .bytesMasked, .textLF:
            var g = goldenBytes(golden, pointer: pointer)
            var a: Data
            switch value {
            case .bytes(let d): a = d
            case .json(let j): a = (try? JSONWriter.data(j)) ?? Data()
            case .zip(let d): a = d
            case .skip: return nil
            }
            if mode == .textLF { g = lf(g); a = lf(a) }
            if mode == .bytes { return GoldenMatcher.byteMismatch(g, a)?.description }
            return GoldenMatcher.match(golden: g, actual: a, context: mc, bindings: ctx.bindings)?.description
        case .jsonSemantic:
            let gv: JSONValue
            do {
                let root = try JSONParser.parse(golden)
                guard let r = pointer.map({ GoldJSONSemantic.resolve($0, in: root) }) ?? root else {
                    return "pointer \(pointer ?? "") does not resolve in the golden"
                }
                gv = r
            } catch { return "golden is not JSON: \(error)" }
            let av: JSONValue
            switch value {
            case .json(let j): av = j
            case .bytes(let d), .zip(let d):
                do { av = try JSONParser.parse(d) } catch { return "actual is not JSON: \(error)" }
            case .skip: return nil
            }
            return GoldJSONSemantic.compare(golden: gv, actual: av, context: mc, bindings: ctx.bindings)?.description
        case .xmlCanonical:
            guard case .bytes(let a) = value else { return "xml-canonical needs bytes" }
            return GoldXMLCanonicalizer.difference(golden: goldenBytes(golden, pointer: pointer), actual: a)?.description
        case .zipManifest, .zipManifestOrdered:
            guard case .zip(let archive) = value else { return "zip modes need a ZIP archive" }
            return compareZip(goldenManifest: golden, goldenFile: goldenFile, archive: archive,
                              ordered: mode == .zipManifestOrdered, ctx: ctx)
        }
    }

    /// GF.3.9 / GF.4.6: significant manifest fields + every payload (AA formats `bytes-masked`, others `bytes`).
    static func compareZip(goldenManifest: Data, goldenFile: String, archive: Data, ordered: Bool,
                           ctx: GoldCaseContext) -> String? {
        let gm: GoldZipManifest, am: GoldZipManifest
        do { gm = try GoldZipManifest(json: try JSONParser.parse(goldenManifest)) } catch { return "golden manifest: \(error)" }
        do { am = try GoldZipManifest(zip: archive, orderSignificant: ordered) } catch { return "actual archive: \(error)" }
        var golden = gm
        golden.orderSignificant = ordered || gm.orderSignificant
        var problems = golden.compare(actual: am)
        let folder = (goldenFile as NSString).deletingLastPathComponent
        if let reader = try? ZipReader(data: archive) {
            for e in gm.entries where !e.isDirectory {
                guard let payloadName = e.payload else { continue }
                let rel = folder.isEmpty ? payloadName : folder + "/" + payloadName
                guard let gp = try? ctx.goldenData(rel) else { problems.append("\(e.name): payload golden \(rel) missing"); continue }
                guard let info = reader.entry(named: e.name), let ap = try? reader.data(for: info) else { continue }
                let mismatch = GoldZipManifest.isAAFormat(e.name)
                    ? GoldenMatcher.match(golden: gp, actual: ap, context: ctx.matchContext, bindings: ctx.bindings)
                    : GoldenMatcher.byteMismatch(gp, ap)
                if let m = mismatch { problems.append("\(e.name) payload: \(m)") }
            }
        } else {
            problems.append("the actual archive cannot be read")
        }
        return problems.isEmpty ? nil : problems.joined(separator: "\n  ")
    }

    static func lf(_ d: Data) -> Data {
        Data(String(decoding: d, as: UTF8.self).replacingOccurrences(of: "\r\n", with: "\n").utf8)
    }

    static func goldenBytes(_ golden: Data, pointer: String?) -> Data {
        guard let pointer, let root = try? JSONParser.parse(golden),
              let v = GoldJSONSemantic.resolve(pointer, in: root) else { return golden }
        if let s = v.stringValue { return Data(s.utf8) }
        return (try? JSONWriter.data(v, options: JSONWriteOptions(indented: true))) ?? golden
    }

    static func actualBytes(_ v: GoldValue) -> Data {
        switch v {
        case .bytes(let d), .zip(let d): return d
        case .json(let j): return (try? JSONWriter.data(j, options: JSONWriteOptions(indented: true))) ?? Data()
        case .skip(let s): return Data(s.utf8)
        }
    }

    /// Records the problems according to the case's normative level (GF.8.6).
    static func report(_ problems: [String], case c: GoldFixtureCase, attachments: [(name: String, data: Data)]) {
        guard !problems.isEmpty else { return }
        for a in attachments { Attachment.record(a.data, named: a.name) }
        let text = "\(c.id) — \(c.title)\n  " + problems.joined(separator: "\n  ")
        switch c.normative {
        case .must:
            Issue.record(Comment(rawValue: text))
        case .should:
            withKnownIssue("should-level case (GF.8.6): reported, not release-blocking", isIntermittent: true) {
                Issue.record(Comment(rawValue: text))
            }
        case .recordOnly:
            Attachment.record(Data(text.utf8), named: "\(c.id).record-only-diff.txt")
        }
    }
}
