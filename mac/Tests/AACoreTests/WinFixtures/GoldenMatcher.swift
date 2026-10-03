// Golden matcher (spec 01 GF.8.2, GF.4.5, GF.4.9, DATA-305/309): compares Mac-produced bytes with a golden that may
// contain volatile-value tokens (`%%NEWGUID:1%%`, `%%NOWUTC%%`, `%%DATADIR%%`, …). The golden is split on tokens, the
// literal parts are escaped, one anchored regex with a capture per token is matched against the actual text, and
// the equality constraints are enforced afterwards (same n ⇒ same value, different n ⇒ different values,
// NEWGUID:n / GUIDN:n share one value). On mismatch it reports the first differing byte offset with 80 bytes of
// context on both sides.
import Foundation
@testable import AACore

// MARK: - Tokens

/// The GF.4.5 token grammar.
enum GoldToken: Hashable, Sendable, CustomStringConvertible {
    case newGuid(Int)
    case guidN(Int)
    case nowLocal
    case nowUTC
    case machine
    case dataDir
    /// W-GOLD extension of the GF.4.5 grammar: the data folder upper-cased (A25 stores it that way to probe
    /// case-insensitive matching). Literal substitution like `%%DATADIR%%`.
    case dataDirUpper
    case temp
    case salt16
    case hash32
    case encBlob

    var description: String {
        switch self {
        case .newGuid(let n): return "%%NEWGUID:\(n)%%"
        case .guidN(let n): return "%%GUIDN:\(n)%%"
        case .nowLocal: return "%%NOWLOCAL%%"
        case .nowUTC: return "%%NOWUTC%%"
        case .machine: return "%%MACHINE%%"
        case .dataDir: return "%%DATADIR%%"
        case .dataDirUpper: return "%%DATADIRUPPER%%"
        case .temp: return "%%TEMP%%"
        case .salt16: return "%%SALT16%%"
        case .hash32: return "%%HASH32%%"
        case .encBlob: return "%%ENCBLOB%%"
        }
    }

    /// The token named by the text between the `%%` delimiters, or nil (then the text is literal — e.g. the S05
    /// salt `"%%%"` is real content, not a token).
    init?(name: String) {
        switch name {
        case "NOWLOCAL": self = .nowLocal
        case "NOWUTC": self = .nowUTC
        case "MACHINE": self = .machine
        case "DATADIR": self = .dataDir
        case "DATADIRUPPER": self = .dataDirUpper
        case "TEMP": self = .temp
        case "SALT16": self = .salt16
        case "HASH32": self = .hash32
        case "ENCBLOB": self = .encBlob
        default:
            let parts = name.split(separator: ":", omittingEmptySubsequences: false)
            guard parts.count == 2, let n = Int(parts[1]), n >= 0, parts[1].allSatisfy(\.isASCII) else { return nil }
            switch parts[0] {
            case "NEWGUID": self = .newGuid(n)
            case "GUIDN": self = .guidN(n)
            default: return nil
            }
        }
    }

    /// GF.4.5 "Matches" column. `%%DATADIR%%` is a literal substitution (raw or JSON-escaped), never a regex.
    func pattern(dataDir: String?) -> String {
        switch self {
        case .newGuid: return "[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}"
        case .guidN: return "[0-9a-f]{32}"
        case .nowLocal: return #"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,7})?[+-]\d{2}:\d{2}"#
        case .nowUTC: return #"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,7})?Z"#
        case .machine: return #"[^"\\\r\n]+"#
        case .temp: return #"[^"\r\n]*"#
        case .salt16: return #"[A-Za-z0-9+/]{22}=="#
        case .hash32: return #"[A-Za-z0-9+/]{43}="#
        case .encBlob: return #"enc:[A-Za-z0-9+/]+={0,2}"#
        case .dataDir, .dataDirUpper:
            guard let dir = dataDir else { return "(?!)" }       // no data folder → can never match
            let forms = GoldenMatcher.dataDirForms(self == .dataDirUpper ? NetText.toUpperInvariant(dir) : dir)
            return "(?:" + forms.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|") + ")"
        }
    }
}

/// A golden split into literal text and tokens.
enum GoldSegment: Hashable, Sendable {
    case literal(String)
    case token(GoldToken)
}

// MARK: - Context, bindings, mismatch

/// What the matcher needs from the test: the Mac data folder that replaces `%%DATADIR%%`, and the test's clock
/// for the ±10 min plausibility check of `%%NOWLOCAL%%`/`%%NOWUTC%%` (GF.4.5).
struct GoldMatchContext: Sendable {
    var dataDir: String?
    var now: Date?
    var nowTolerance: TimeInterval = 600

    static let plain = GoldMatchContext()
}

/// Token values captured so far for one case: equality constraints hold across every output of the case.
final class GoldBindings: @unchecked Sendable {
    private(set) var guids: [Int: String] = [:]          // n → lower-case "D" form
    private(set) var other: [String: String] = [:]       // MACHINE etc. — informational

    /// Binds `value` to GUID number `n` (`D` or `N` form). Returns a violation message or nil.
    func bindGuid(_ n: Int, _ raw: String) -> String? {
        let d = GoldBindings.dashed(raw.lowercased())
        if let existing = guids[n] {
            return existing == d ? nil : "%%NEWGUID:\(n)%% is bound to \(existing) but here is \(d)"
        }
        if let (m, _) = guids.first(where: { $0.value == d }) {
            return "%%NEWGUID:\(n)%% and %%NEWGUID:\(m)%% must differ but both are \(d)"
        }
        guids[n] = d
        return nil
    }

    func note(_ token: GoldToken, _ value: String) { other[token.description] = value }

    static func dashed(_ s: String) -> String {
        guard s.count == 32 else { return s }
        let a = Array(s)
        return String(a[0..<8]) + "-" + String(a[8..<12]) + "-" + String(a[12..<16]) + "-" + String(a[16..<20]) + "-" + String(a[20..<32])
    }
}

/// A comparison failure, with enough context to fix it without opening both files.
struct GoldMismatch: Error, CustomStringConvertible, Sendable {
    var reason: String
    /// First differing byte offset in the actual output (UTF-8), when known.
    var offset: Int?
    var expectedContext: String?
    var actualContext: String?
    /// JSON path for semantic comparisons (`/Roots/0/Text`).
    var path: String?

    var description: String {
        var s = reason
        if let path { s += " at \(path)" }
        if let offset { s += " (first difference at byte \(offset))" }
        if let e = expectedContext { s += "\n  expected: …\(e)…" }
        if let a = actualContext { s += "\n  actual:   …\(a)…" }
        return s
    }
}

// MARK: - Matcher

enum GoldenMatcher {
    static let contextBytes = 80

    /// Splits a golden on `%%NAME%%` tokens. Unknown names stay literal.
    static func segments(_ golden: String) -> [GoldSegment] {
        var out: [GoldSegment] = []
        var literal = ""
        var i = golden.startIndex
        while i < golden.endIndex {
            if golden[i...].hasPrefix("%%"),
               let close = golden[golden.index(i, offsetBy: 2)...].range(of: "%%") {
                let name = String(golden[golden.index(i, offsetBy: 2)..<close.lowerBound])
                if !name.isEmpty, let token = GoldToken(name: name) {
                    if !literal.isEmpty { out.append(.literal(literal)); literal = "" }
                    out.append(.token(token))
                    i = close.upperBound
                    continue
                }
            }
            literal.append(golden[i])
            i = golden.index(after: i)
        }
        if !literal.isEmpty { out.append(.literal(literal)) }
        return out
    }

    static func hasTokens(_ golden: String) -> Bool {
        segments(golden).contains { if case .token = $0 { return true }; return false }
    }

    /// The forms a data folder can take inside an output: raw, and as escaped inside a JSON string by the
    /// default .NET encoder (backslashes doubled, non-ASCII as `\uXXXX`).
    static func dataDirForms(_ dir: String) -> [String] {
        var forms = [dir]
        // The same folder seen through /private (macOS temp folders live under the /var → /private/var symlink).
        let resolved = URL(fileURLWithPath: dir).resolvingSymlinksInPath().path
        if resolved != dir { forms.append(resolved) }
        if dir.hasPrefix("/var/") || dir.hasPrefix("/tmp/") { forms.append("/private" + dir) }
        for f in forms where f.hasPrefix("/private/") { forms.append(String(f.dropFirst("/private".count))) }
        forms = Array(Set(forms))
        for raw in forms {
            let escaped = String(JSONWriter.escape(raw).dropFirst().dropLast())
            if !forms.contains(escaped) { forms.append(escaped) }
            // The relaxed escaping of expectation JSON (GF.3.8) only doubles backslashes.
            let relaxed = raw.replacingOccurrences(of: "\\", with: "\\\\")
            if !forms.contains(relaxed) { forms.append(relaxed) }
        }
        return forms.sorted { $0.count != $1.count ? $0.count > $1.count : $0 < $1 }
    }

    /// Compares bytes. Without tokens this is exact byte equality (`bytes`); with tokens the GF.4.5 grammar applies.
    static func match(golden: Data, actual: Data, context: GoldMatchContext = .plain,
                      bindings: GoldBindings = GoldBindings()) -> GoldMismatch? {
        if golden == actual { return nil }
        guard let g = String(data: golden, encoding: .utf8) else { return byteMismatch(golden, actual) }
        if !hasTokens(g) { return byteMismatch(golden, actual) }
        guard let a = String(data: actual, encoding: .utf8) else {
            return GoldMismatch(reason: "actual output is not valid UTF-8 but the golden carries tokens")
        }
        return match(golden: g, actual: a, context: context, bindings: bindings)
    }

    /// Compares text with tokens (`bytes-masked`).
    static func match(golden: String, actual: String, context: GoldMatchContext = .plain,
                      bindings: GoldBindings = GoldBindings()) -> GoldMismatch? {
        let segs = segments(golden)
        var pattern = "\\A"
        var tokens: [GoldToken] = []
        for s in segs {
            switch s {
            case .literal(let t): pattern += NSRegularExpression.escapedPattern(for: t)
            case .token(let k):
                if k == .dataDir || k == .dataDirUpper { pattern += k.pattern(dataDir: context.dataDir) }
                else { pattern += "(" + k.pattern(dataDir: context.dataDir) + ")"; tokens.append(k) }
            }
        }
        pattern += "\\z"
        guard let re = try? NSRegularExpression(pattern: pattern, options: []) else {
            return GoldMismatch(reason: "golden could not be compiled into a matcher")
        }
        let ns = actual as NSString
        guard let m = re.firstMatch(in: actual, options: [], range: NSRange(location: 0, length: ns.length)) else {
            return locate(segments: segs, actual: actual, context: context)
        }
        // Equality constraints and plausibility checks.
        for (i, token) in tokens.enumerated() {
            let r = m.range(at: i + 1)
            guard r.location != NSNotFound else { continue }
            let value = ns.substring(with: r)
            switch token {
            case .newGuid(let n), .guidN(let n):
                if let v = bindings.bindGuid(n, value) {
                    return GoldMismatch(reason: v, offset: utf8Offset(actual, utf16: r.location),
                                        actualContext: contextAround(Array(actual.utf8), utf8Offset(actual, utf16: r.location)))
                }
            case .nowLocal, .nowUTC:
                bindings.note(token, value)
                if let now = context.now, let d = parseISO(value), abs(d.timeIntervalSince(now)) > context.nowTolerance {
                    return GoldMismatch(reason: "\(token) value \(value) is not within ±\(Int(context.nowTolerance / 60)) min of the test clock",
                                        offset: utf8Offset(actual, utf16: r.location))
                }
            default:
                bindings.note(token, value)
            }
        }
        return nil
    }

    /// Byte-for-byte comparison report.
    static func byteMismatch(_ golden: Data, _ actual: Data) -> GoldMismatch? {
        if golden == actual { return nil }
        let g = [UInt8](golden), a = [UInt8](actual)
        let off = firstDifference(g, a) ?? min(g.count, a.count)
        let why = g.count == a.count ? "bytes differ" : "bytes differ (golden \(g.count) B, actual \(a.count) B)"
        return GoldMismatch(reason: why, offset: off, expectedContext: contextAround(g, off), actualContext: contextAround(a, off))
    }

    static func firstDifference(_ a: [UInt8], _ b: [UInt8]) -> Int? {
        let n = min(a.count, b.count)
        var i = 0
        while i < n && a[i] == b[i] { i += 1 }
        return i == n && a.count == b.count ? nil : i
    }

    /// `contextBytes` bytes before and after `offset`, lossily decoded and with control characters made visible.
    static func contextAround(_ bytes: [UInt8], _ offset: Int) -> String {
        let lo = max(0, offset - contextBytes), hi = min(bytes.count, offset + contextBytes)
        guard lo <= hi else { return "" }
        let s = String(decoding: bytes[lo..<hi], as: UTF8.self)
        return s.replacingOccurrences(of: "\r", with: "␍").replacingOccurrences(of: "\n", with: "␊")
            .replacingOccurrences(of: "\t", with: "␉")
    }

    static func utf8Offset(_ s: String, utf16 location: Int) -> Int {
        let u = s.utf16
        let idx = u.index(u.startIndex, offsetBy: min(location, u.count))
        return s.utf8.distance(from: s.utf8.startIndex, to: idx.samePosition(in: s.utf8) ?? s.utf8.endIndex)
    }

    /// Walks the segments in order to find where the actual text stops matching (the verdict itself comes from the
    /// single backtracking regex; this only produces the report).
    static func locate(segments segs: [GoldSegment], actual: String, context: GoldMatchContext) -> GoldMismatch {
        let a = Array(actual.utf8)
        var pos = 0
        var goldenSoFar: [UInt8] = []
        for (k, s) in segs.enumerated() {
            switch s {
            case .literal(let t):
                let lit = Array(t.utf8)
                var i = 0
                while i < lit.count && pos + i < a.count && a[pos + i] == lit[i] { i += 1 }
                if i < lit.count {
                    let off = pos + i
                    var expected = goldenSoFar + lit
                    if k + 1 < segs.count, case .token(let next) = segs[k + 1] { expected += Array(next.description.utf8) }
                    return GoldMismatch(reason: pos + i >= a.count ? "actual output ends early" : "literal text differs",
                                        offset: off,
                                        expectedContext: contextAround(expected, goldenSoFar.count + i),
                                        actualContext: contextAround(a, off))
                }
                pos += lit.count
                goldenSoFar += lit
            case .token(let t):
                let rest = String(decoding: a[pos...], as: UTF8.self)
                let re = try? NSRegularExpression(pattern: t.pattern(dataDir: context.dataDir), options: [.anchorsMatchLines])
                let ns = rest as NSString
                if let re, let m = re.firstMatch(in: rest, options: [.anchored], range: NSRange(location: 0, length: ns.length)) {
                    pos += utf8Offset(rest, utf16: m.range.length)
                    goldenSoFar += Array(t.description.utf8)
                } else {
                    return GoldMismatch(reason: "no value of the shape \(t) here", offset: pos,
                                        expectedContext: contextAround(goldenSoFar + Array(t.description.utf8), goldenSoFar.count),
                                        actualContext: contextAround(a, pos))
                }
            }
        }
        if pos < a.count {
            return GoldMismatch(reason: "actual output has \(a.count - pos) extra byte(s)", offset: pos,
                                expectedContext: contextAround(goldenSoFar, goldenSoFar.count), actualContext: contextAround(a, pos))
        }
        return GoldMismatch(reason: "the output matches piecewise but not as a whole (a token swallowed a following literal)")
    }

    /// `yyyy-MM-ddTHH:mm:ss[.f{1,7}](Z|±hh:mm)` → instant (Gregorian, no time-zone database involved).
    static func parseISO(_ s: String) -> Date? {
        let re = try? NSRegularExpression(pattern: #"^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.(\d{1,7}))?(Z|([+-])(\d{2}):(\d{2}))$"#)
        let ns = s as NSString
        guard let m = re?.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) else { return nil }
        func int(_ i: Int) -> Int { Int(ns.substring(with: m.range(at: i))) ?? 0 }
        guard let civil = CivilDate(year: int(1), month: int(2), day: int(3)) else { return nil }
        var seconds = Double(civil.daysFromCivil - CivilDate(year: 1970, month: 1, day: 1)!.daysFromCivil) * 86_400
        seconds += Double(int(4) * 3600 + int(5) * 60 + int(6))
        if m.range(at: 7).location != NSNotFound {
            let f = ns.substring(with: m.range(at: 7))
            seconds += (Double("0." + f) ?? 0)
        }
        if ns.substring(with: m.range(at: 8)) != "Z" {
            let sign = ns.substring(with: m.range(at: 9)) == "-" ? -1.0 : 1.0
            seconds -= sign * Double(int(10) * 3600 + int(11) * 60)
        }
        return Date(timeIntervalSince1970: seconds)
    }
}

// MARK: - JSON-semantic comparison (GF.3.8)

enum GoldJSONSemantic {
    /// Same keys (order ignored), same array order, strings compared exactly as UTF-16 code units (tokens allowed in
    /// golden strings), numbers compared as decimal text (equal lexemes, or equal decimal values when the lexemes
    /// differ only in notation).
    static func compare(golden: JSONValue, actual: JSONValue, path: String = "",
                        context: GoldMatchContext = .plain, bindings: GoldBindings = GoldBindings()) -> GoldMismatch? {
        let here = path.isEmpty ? "/" : path
        switch (golden, actual) {
        case (.null, .null): return nil
        case (.bool(let g), .bool(let a)):
            return g == a ? nil : GoldMismatch(reason: "expected \(g), got \(a)", path: here)
        case (.number(let g), .number(let a)):
            if g.lexeme == a.lexeme { return nil }
            if let dg = Decimal(string: g.lexeme, locale: Locale(identifier: "en_US_POSIX")),
               let da = Decimal(string: a.lexeme, locale: Locale(identifier: "en_US_POSIX")), dg == da { return nil }
            return GoldMismatch(reason: "expected number \(g.lexeme), got \(a.lexeme)", path: here)
        case (.string(let g), _), (.rawString(let g), _):
            guard let a = actual.stringValue else { return GoldMismatch(reason: "expected a string, got \(kind(actual))", path: here) }
            if Ordinal.equals(g, a) { return nil }
            if GoldenMatcher.hasTokens(g) {
                if var m = GoldenMatcher.match(golden: g, actual: a, context: context, bindings: bindings) {
                    m.path = here; return m
                }
                return nil
            }
            return GoldMismatch(reason: "strings differ: expected \(quote(g)), got \(quote(a))", path: here)
        case (.array(let g), .array(let a)):
            if g.count != a.count {
                return GoldMismatch(reason: "array length: expected \(g.count), got \(a.count)", path: here)
            }
            for (i, (x, y)) in zip(g, a).enumerated() {
                if let m = compare(golden: x, actual: y, path: path + "/\(i)", context: context, bindings: bindings) { return m }
            }
            return nil
        case (.object(var g), .object(var a)):
            // GF.4.7: exception messages (and .NET type names) are compared only when the text is written in AA's
            // own source (`aaAuthored`); a framework exception only has to be an exception on both sides.
            if g["aaAuthored"]?.boolValue == false {
                for k in ["type", "message"] { _ = g.removeValue(forKey: k); _ = a.removeValue(forKey: k) }
                _ = g.removeValue(forKey: "aaAuthored"); _ = a.removeValue(forKey: "aaAuthored")
            }
            let missing = g.keys.filter { !a.containsKey($0) }
            if !missing.isEmpty { return GoldMismatch(reason: "missing key(s) \(missing)", path: here) }
            let extra = a.keys.filter { !g.containsKey($0) }
            if !extra.isEmpty { return GoldMismatch(reason: "unexpected key(s) \(extra)", path: here) }
            for (k, v) in g {
                if let m = compare(golden: v, actual: a[k] ?? .null, path: path + "/" + escapePointer(k),
                                   context: context, bindings: bindings) { return m }
            }
            return nil
        default:
            return GoldMismatch(reason: "expected \(kind(golden)), got \(kind(actual))", path: here)
        }
    }

    static func kind(_ v: JSONValue) -> String {
        switch v {
        case .null: return "null"
        case .bool: return "a boolean"
        case .number: return "a number"
        case .string, .rawString: return "a string"
        case .array: return "an array"
        case .object: return "an object"
        }
    }

    static func quote(_ s: String) -> String { JSONWriter.escape(s) }

    static func escapePointer(_ k: String) -> String {
        k.replacingOccurrences(of: "~", with: "~0").replacingOccurrences(of: "/", with: "~1")
    }

    /// RFC 6901 pointer resolution (`/A13.4`, `/Roots/0/Text`).
    static func resolve(_ pointer: String, in root: JSONValue) -> JSONValue? {
        if pointer.isEmpty { return root }
        guard pointer.hasPrefix("/") else { return nil }
        var cur = root
        for raw in pointer.dropFirst().split(separator: "/", omittingEmptySubsequences: false) {
            let token = raw.replacingOccurrences(of: "~1", with: "/").replacingOccurrences(of: "~0", with: "~")
            switch cur {
            case .object(let o):
                guard let next = o[token] else { return nil }
                cur = next
            case .array(let a):
                guard let i = Int(token), i >= 0, i < a.count else { return nil }
                cur = a[i]
            default: return nil
            }
        }
        return cur
    }
}
