// Spec: 10 §X.4.5 (cell loading per `<c>`: `t` kinds, number parsing, styles, 1904 shift), VESSEL-305/306,
//       VESSEL-313 (inline strings), VESSEL-316/317 (errors, `t="d"`), VESSEL-318 (formulas), VESSEL-321
//       (addressing quirks), VESSEL-322 (merges: no effect), VESSEL-323 (comments), VESSEL-324 (table side effects).
import Foundation

enum SvcXlsxSheet {
    struct Loaded {
        var cells: [Int64: XlsxCell]
        var uncachedFormulas: Set<Int64>
    }

    /// Parses one worksheet part into its cell map.
    static func parse(_ data: Data, sharedStrings: [String], styles: SvcXlsxStyleTable,
                      use1904: Bool) throws(XlsxReadError) -> Loaded {
        let scanner = try SvcXmlScanner(data)
        var cells: [Int64: XlsxCell] = [:]
        var uncached = Set<Int64>()
        var path: [String] = []
        var unnumberedRows = 0          // VESSEL-321: only advanced by <row> elements without r
        var rowIndex = 0
        var lastColumn = 0

        // Current <c> state.
        var inCell = false
        var key: Int64 = 0
        var styleIndex = 0
        var type = "n"
        var hasFormula = false
        var value: String?
        var capturingV = false
        var inlineIs = false
        var inlineT: String?
        var inlineRuns: [String] = []
        var inlineHasRuns = false
        var capturingInline = 0         // 0 none, 1 <is><t>, 2 <is><r><t>
        var buffer = ""

        while let ev = try scanner.next() {
            switch ev {
            case .start(let name, let attrs):
                func attr(_ n: String) -> String? {
                    for a in attrs where a.local == n { return a.value }
                    return nil
                }
                switch name {
                case "row" where path.last == "sheetData":
                    if let r = attr("r") {
                        guard let v = Int(r.trimmingCharacters(in: .whitespaces)), v > 0 else {
                            throw .corrupt(detail: "Invalid row number \"\(r)\".")
                        }
                        rowIndex = v
                    } else {
                        unnumberedRows += 1
                        rowIndex = unnumberedRows
                    }
                    lastColumn = 0
                case "c" where path.last == "row":
                    var r = rowIndex, c = lastColumn + 1
                    if let ref = attr("r") {
                        guard let rc = SvcCellKey.parse(ref) else { throw .corrupt(detail: "Invalid cell reference \"\(ref)\".") }
                        (r, c) = rc
                    }
                    lastColumn = c
                    key = SvcCellKey.make(r, c)
                    if let s = attr("s") {
                        guard let v = Int(s) else { throw .corrupt(detail: "Invalid cell style \"\(s)\".") }
                        styleIndex = v
                        _ = try styles.kind(v)                 // an index past cellXfs fails the import
                    } else {
                        styleIndex = 0
                    }
                    type = attr("t") ?? "n"
                    hasFormula = false; value = nil; inlineIs = false; inlineT = nil
                    inlineRuns = []; inlineHasRuns = false
                    inCell = true
                case "f" where inCell && path.last == "c":
                    hasFormula = true
                case "v" where inCell && path.last == "c":
                    capturingV = true
                    buffer = ""
                case "is" where inCell && path.last == "c":
                    inlineIs = true
                case "r" where inlineIs && path.last == "is":
                    inlineHasRuns = true
                    inlineRuns.append("")
                case "t" where inlineIs:
                    if path.last == "is" { capturingInline = 1; buffer = "" }
                    else if path.last == "r", path.count >= 2, path[path.count - 2] == "is" { capturingInline = 2; buffer = "" }
                default:
                    break
                }
                path.append(name)
            case .text(let s):
                if capturingV || capturingInline != 0 { buffer += s }
            case .end(let name):
                path.removeLast()
                switch name {
                case "v" where capturingV:
                    value = (value ?? "") + buffer
                    capturingV = false
                case "t" where capturingInline != 0:
                    if capturingInline == 1 { inlineT = (inlineT ?? "") + buffer }
                    else if !inlineRuns.isEmpty { inlineRuns[inlineRuns.count - 1] += buffer }
                    capturingInline = 0
                case "c" where inCell:
                    inCell = false
                    // VESSEL-313: a direct <t> wins; else the rich runs; an empty <is> → "".
                    let inlineText: String? = inlineIs ? (inlineT ?? (inlineHasRuns ? inlineRuns.joined() : "")) : nil
                    let newValue = try cellValue(type: type, value: value, inline: inlineText,
                                                 sharedStrings: sharedStrings, styles: styles, styleIndex: styleIndex,
                                                 use1904: use1904)
                    if newValue == nil && !hasFormula && cells[key] == nil { break }
                    var cell = cells[key] ?? XlsxCell()
                    if let v = newValue { cell.value = v }
                    if hasFormula { cell.hasFormula = true }
                    cells[key] = cell
                    if hasFormula && value == nil { uncached.insert(key) } else if newValue != nil { uncached.remove(key) }
                default:
                    break
                }
            }
        }
        return Loaded(cells: cells, uncachedFormulas: uncached)
    }

    /// X.4.5: the value a `<c>` sets, or nil when it sets none (the earlier value / blank stays).
    private static func cellValue(type: String, value: String?, inline: String?,
                                  sharedStrings: [String], styles: SvcXlsxStyleTable, styleIndex: Int,
                                  use1904: Bool) throws(XlsxReadError) -> XlsxValue? {
        var result: XlsxValue?
        switch type {
        case "n":
            guard let v = value, let d = try parseNumber(v) else { return nil }
            switch try styles.kind(styleIndex) {
            case .number: result = .number(d)
            case .dateTime: result = .dateTime(serial: d)
            case .timeSpan: result = .timeSpan(serial: d)
            }
        case "s":
            if let v = value, let k = parseIndex(v), k < sharedStrings.count { result = .text(sharedStrings[k]) }
            else { result = .text("") }
        case "str":
            result = .text(value ?? "")
        case "inlineStr":
            guard let text = inline else { return nil }
            result = .text(SvcXlsxText.fixNewLines(text))
        case "b":
            guard let v = value else { return nil }
            result = .boolean(v == "1" || v.caseInsensitiveCompare("TRUE") == .orderedSame)
        case "e":
            guard let v = value, let code = XlsxErrorCode(rawValue: NetText.trim(v)) else { return nil }
            result = .error(code)
        case "d":
            guard let v = value else { return nil }
            guard let dt = parseIsoExact(v) else {
                throw .corrupt(detail: "The date \"\(v)\" in an ISO date cell is not in a supported format.")
            }
            result = .dateTime(serial: ExcelSerial.toSerial(dt))
        default:
            throw .corrupt(detail: "Unknown cell type.")
        }
        if use1904, case .dateTime(let x)? = result {
            let base = try ExcelSerial.fromSerial(x)
            guard base.ticks <= NetDateTime.maxTicks - 1462 * NetDateTime.ticksPerDay else {
                throw .message("The added or subtracted value results in an un-representable DateTime.")
            }
            result = .dateTime(serial: ExcelSerial.toSerial(base.addingDays(1462)))
        }
        return result
    }

    /// .NET `double.TryParse(v, Float | AllowLeadingWhite | AllowTrailingWhite, Invariant)`: optional white space,
    /// optional sign, digits with an optional `.` fraction, optional exponent. `Infinity` / `NaN` (and overflow to ∞)
    /// parse but fail the import (ClosedXML rejects non-finite values). Anything else → nil (the cell stays blank).
    static func parseNumber(_ raw: String) throws(XlsxReadError) -> Double? {
        if let fast = fastNumber(raw) { return fast }
        let s = raw.trimmingCharacters(in: CharacterSet(charactersIn: " \t\n\r\u{0B}\u{0C}"))
        let lower = s.lowercased()
        if ["infinity", "+infinity", "-infinity", "nan", "+nan", "-nan", "\u{221E}", "-\u{221E}", "+\u{221E}"].contains(lower) {
            throw .corrupt(detail: "A cell holds a non-finite number (\(s)).")
        }
        guard let canonical = canonicalNumber(s), let d = Double(canonical) else { return nil }
        guard d.isFinite else { throw .corrupt(detail: "A cell holds a number that is too large (\(s)).") }
        return d
    }

    /// The common case — plain ASCII `[-]digits[.digits]` with no white space — without any allocation.
    static func fastNumber(_ s: String) -> Double? {
        var digits = 0, dots = 0, first = true
        for c in s.utf8 {
            if c >= 0x30 && c <= 0x39 { digits += 1 } else if c == 0x2E { dots += 1 } else if c == 0x2D && first {
            } else { return nil }
            first = false
        }
        guard digits > 0, dots <= 1, digits <= 15 else { return nil }
        return Double(s)
    }

    /// `[sign] digits [. digits] [e [sign] digits]` (ASCII digits; at least one digit in the mantissa) → a string
    /// `Double(_:)` accepts, or nil.
    static func canonicalNumber(_ s: String) -> String? {
        let u = Array(s.utf8)
        var k = 0
        var out = ""
        if k < u.count, u[k] == 0x2B || u[k] == 0x2D { if u[k] == 0x2D { out = "-" }; k += 1 }
        var intDigits = "", fracDigits = ""
        while k < u.count, u[k] >= 0x30, u[k] <= 0x39 { intDigits.append(Character(UnicodeScalar(u[k]))); k += 1 }
        if k < u.count, u[k] == 0x2E {
            k += 1
            while k < u.count, u[k] >= 0x30, u[k] <= 0x39 { fracDigits.append(Character(UnicodeScalar(u[k]))); k += 1 }
        }
        guard !intDigits.isEmpty || !fracDigits.isEmpty else { return nil }
        out += (intDigits.isEmpty ? "0" : intDigits) + (fracDigits.isEmpty ? "" : "." + fracDigits)
        if k < u.count, u[k] == 0x65 || u[k] == 0x45 {
            k += 1
            var exp = "e"
            if k < u.count, u[k] == 0x2B || u[k] == 0x2D { if u[k] == 0x2D { exp += "-" }; k += 1 }
            var expDigits = ""
            while k < u.count, u[k] >= 0x30, u[k] <= 0x39 { expDigits.append(Character(UnicodeScalar(u[k]))); k += 1 }
            guard !expDigits.isEmpty else { return nil }
            out += exp + expDigits
        }
        return k == u.count ? out : nil
    }

    /// `Int32.TryParse` with the same styles: an integral value (a decimal point followed by zeros, an exponent)
    /// within Int32; negative → nil (no shared string).
    static func parseIndex(_ s: String) -> Int? {
        if !s.isEmpty, s.utf8.count <= 9, s.utf8.allSatisfy({ $0 >= 0x30 && $0 <= 0x39 }) { return Int(s) }
        guard let canonical = canonicalNumber(s.trimmingCharacters(in: CharacterSet(charactersIn: " \t\n\r\u{0B}\u{0C}"))),
              let d = Double(canonical), d.isFinite, d == d.rounded(.towardZero),
              d >= 0, d <= Double(Int32.max) else { return nil }
        return Int(d)
    }

    /// VESSEL-317: `DateTime.ParseExact` (invariant, surrounding white space allowed) with exactly
    /// `yyyy-MM-ddTHH:mm:ss.fff`, `yyyy-MM-ddTHH:mm`, `yyyy-MM-dd`.
    static func parseIsoExact(_ raw: String) -> NetDateTime? {
        let s = Array(raw.trimmingCharacters(in: CharacterSet(charactersIn: " \t\n\r\u{0B}\u{0C}")).utf8)
        func num(_ a: Int, _ n: Int) -> Int? { CivilDate.digits(s, a, n) }
        guard s.count == 10 || s.count == 16 || s.count == 23, s.count >= 10, s[4] == 0x2D, s[7] == 0x2D,
              let y = num(0, 4), let mo = num(5, 2), let d = num(8, 2), let date = CivilDate(year: y, month: mo, day: d)
        else { return nil }
        if s.count == 10 { return NetDateTime.calendarDate(date) }
        guard s[10] == 0x54, s[13] == 0x3A, let h = num(11, 2), let mi = num(14, 2), h < 24, mi < 60 else { return nil }
        var sec = 0, ms = 0
        if s.count == 23 {
            guard s[16] == 0x3A, s[19] == 0x2E, let ss = num(17, 2), let f = num(20, 3), ss < 60 else { return nil }
            sec = ss; ms = f
        }
        return NetDateTime(year: y, month: mo, day: d, hour: h, minute: mi, second: sec,
                           fractionTicks: Int64(ms) * 10_000, kind: .unspecified)
    }

    // MARK: Comments and tables (applied after all cells)

    /// VESSEL-323: every `comment@ref` of the sheet's legacy comments part marks that cell.
    static func applyComments(_ data: Data, to cells: inout [Int64: XlsxCell]) throws(XlsxReadError) {
        let scanner = try SvcXmlScanner(data)
        while let ev = try scanner.next() {
            guard case .start(let name, let attrs) = ev, name == "comment",
                  let ref = attrs.first(where: { $0.local == "ref" })?.value else { continue }
            let first = ref.split(separator: ":").first.map(String.init) ?? ref
            guard let rc = SvcCellKey.parse(first) else { continue }
            let key = SvcCellKey.make(rc.row, rc.column)
            var cell = cells[key] ?? XlsxCell()
            cell.hasComment = true
            cells[key] = cell
        }
    }

    /// VESSEL-324: a one-row table inserts one row below it within its column span; every empty-by-contents cell of
    /// the table's first row gets `Column{n}`, unique only against the header texts to its left.
    static func applyTable(_ data: Data, to cells: inout [Int64: XlsxCell]) throws(XlsxReadError) {
        let scanner = try SvcXmlScanner(data)
        var ref: String?
        while let ev = try scanner.next() {
            if case .start(let name, let attrs) = ev, name == "table" {
                ref = attrs.first(where: { $0.local == "ref" })?.value
                break
            }
        }
        guard let ref else { return }
        let ends = ref.split(separator: ":").map(String.init)
        guard let a = SvcCellKey.parse(ends.first ?? ""), let b = SvcCellKey.parse(ends.count > 1 ? ends[1] : ends[0])
        else { return }
        let top = min(a.row, b.row), bottom = max(a.row, b.row)
        let left = min(a.column, b.column), right = max(a.column, b.column)
        if top == bottom {
            let movers = cells.keys.filter { k in
                let (r, c) = SvcCellKey.split(k)
                return r > bottom && c >= left && c <= right
            }.sorted { SvcCellKey.split($0).row > SvcCellKey.split($1).row }
            for k in movers {
                let (r, c) = SvcCellKey.split(k)
                cells[SvcCellKey.make(r + 1, c)] = cells.removeValue(forKey: k)
            }
        }
        var leftTexts: [String] = []
        for c in left...right {
            let key = SvcCellKey.make(top, c)
            let cell = cells[key] ?? XlsxCell()
            let emptyByContents = (cell.value == .blank || cell.value == .text("")) && !cell.hasFormula
            if emptyByContents {
                var n = c - left + 1
                while leftTexts.contains(where: { Ordinal.equals($0, "Column\(n)") }) { n += 1 }
                var filled = cell
                filled.value = .text("Column\(n)")
                cells[key] = filled
                leftTexts.append("Column\(n)")
            } else {
                leftTexts.append(XlsxRender.getString(cell))
            }
        }
    }
}
