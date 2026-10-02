// Spec: 10 §X.4.3 (styles → numeric kind: built-in ids, `<numFmts>` overrides with a non-empty code), §X.4.4 (exact
//       port of ClosedXML `GetDataTypeFromFormat`), VESSEL-307/308, X.8.2; X.2 D1/D2.
import Foundation

public enum NumberKind: Sendable, Hashable { case number, dateTime, timeSpan }

public enum XlsxStyles {
    /// Built-in `numFmtId` → kind: 18–21, 45–47 → timeSpan; 14–16, 22 → dateTime; everything else (incl. 17,
    /// 27–36, 49, 50–58) → number.
    public static func builtinKind(_ numFmtId: Int) -> NumberKind {
        switch numFmtId {
        case 18, 19, 20, 21, 45, 46, 47: return .timeSpan
        case 14, 15, 16, 22: return .dateTime
        default: return .number
        }
    }

    /// Exact port of ClosedXML `GetDataTypeFromFormat` (X.4.4): whitespace-only → number; lower-cased, scanned left to
    /// right — `"…"` and `[…]` skipped (an unterminated one → number; Windows hangs on `"`), `0 # ?` → number,
    /// `y d` → dateTime, `h s` → timeSpan, `m` looks ahead (more `m`s skipped; `s` → timeSpan; any other ASCII letter
    /// or digit → dateTime; other characters skipped; end → dateTime); no decision → number. No `\` escapes, no
    /// section splitting.
    public static func classifyCustom(_ code: String) -> NumberKind {
        if NetText.isBlank(code) { return .number }
        return scan(code) ?? .number
    }

    static func scan(_ code: String) -> NumberKind? {
        let f = Array(code.lowercased().unicodeScalars)
        var i = 0
        while i < f.count {
            switch f[i] {
            case "\"":
                guard let k = f[(i + 1)...].firstIndex(of: "\"") else { return nil }
                i = k
            case "[":
                guard let k = f[(i + 1)...].firstIndex(of: "]") else { return nil }
                i = k
            case "0", "#", "?": return .number
            case "y", "d": return .dateTime
            case "h", "s": return .timeSpan
            case "m":
                var j = i + 1
                while j < f.count {
                    let c = f[j]
                    if c == "m" { j += 1; continue }
                    if c == "s" { return .timeSpan }
                    if ("a"..."z").contains(c) || ("0"..."9").contains(c) { return .dateTime }
                    j += 1
                }
                return .dateTime
            default:
                break
            }
            i += 1
        }
        return nil
    }
}

/// The parsed styles part: the numeric kind of every `cellXfs` position (nil = no styles part or no `<cellXfs>`).
struct SvcXlsxStyleTable: Sendable {
    var kinds: [NumberKind]?

    init(kinds: [NumberKind]? = nil) { self.kinds = kinds }

    init(data: Data) throws(XlsxReadError) {
        var scanner = try SvcXmlScanner(data)
        var numFmts: [Int: String] = [:]
        var xfIDs: [Int]?
        var path: [String] = []
        while let ev = try scanner.next() {
            switch ev {
            case .start(let name, let attrs):
                func attr(_ n: String) -> String? { attrs.first { SvcXmlScanner.local($0.name) == n }?.value }
                if name == "numFmt", path.last == "numFmts", let id = attr("numFmtId").flatMap({ Int($0) }),
                   numFmts[id] == nil {
                    numFmts[id] = attr("formatCode") ?? ""
                } else if name == "cellXfs" {
                    if xfIDs == nil { xfIDs = [] }
                } else if name == "xf", path.last == "cellXfs" {
                    xfIDs?.append(attr("numFmtId").flatMap { Int($0) } ?? 0)
                }
                path.append(name)
            case .end:
                path.removeLast()
            case .text:
                break
            }
        }
        kinds = xfIDs?.map { id in
            if let code = numFmts[id], !code.isEmpty { return XlsxStyles.classifyCustom(code) }
            return XlsxStyles.builtinKind(id)
        }
    }

    /// X.4.3 `kind(forStyleIndex:)`: number without a style table; an index past the end fails the import.
    func kind(_ s: Int) throws(XlsxReadError) -> NumberKind {
        guard let kinds else { return .number }
        guard s >= 0, s < kinds.count else {
            throw .corrupt(detail: "Cell style \(s) does not exist (the workbook defines \(kinds.count)).")
        }
        return kinds[s]
    }
}
