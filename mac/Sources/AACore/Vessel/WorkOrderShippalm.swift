// Spec: 10 §3.4 (ShippalmReader.Read / Write / ParseBool / ExcelDate), §4.4 (import expectations, AA export layout:
//       sheet `report`, bold header row, 16 columns A→P, Due Date / Last Done Date text format `@`, Overdue Days
//       numeric, auto-fit widths), VESSEL-101, VESSEL-103, VESSEL-304 (Shippalm sheet policy), VESSEL-327 (renderer B
//       + ExcelDate), VESSEL-318, §7.8–7.9, §7.16, X.8.7 round trip.
import Foundation

/// One parsed Shippalm work order (a `Sendable` value; the main actor turns it into a `ShipJob`).
public struct WorkOrderDraft: Sendable, Hashable {
    public var jobNo = "", title = "", workPlanNo = "", status = "", classCode = "", category = ""
    public var responsibleRank = "", functionNo = "", functionDescription = "", interval = "", dueStatus = ""
    public var dueDate = "", finishedDate = "", lastDoneDate = ""
    public var overdueDays = 0
    public var notify = false
    public var importedAt = ""

    public init(jobNo: String = "", title: String = "", workPlanNo: String = "", status: String = "",
                classCode: String = "", category: String = "", responsibleRank: String = "", functionNo: String = "",
                functionDescription: String = "", interval: String = "", dueStatus: String = "", dueDate: String = "",
                finishedDate: String = "", lastDoneDate: String = "", overdueDays: Int = 0, notify: Bool = false,
                importedAt: String = "") {
        self.jobNo = jobNo; self.title = title; self.workPlanNo = workPlanNo; self.status = status
        self.classCode = classCode; self.category = category; self.responsibleRank = responsibleRank
        self.functionNo = functionNo; self.functionDescription = functionDescription; self.interval = interval
        self.dueStatus = dueStatus; self.dueDate = dueDate; self.finishedDate = finishedDate
        self.lastDoneDate = lastDoneDate; self.overdueDays = overdueDays; self.notify = notify
        self.importedAt = importedAt
    }

    /// A new `ShipJob` (`IsCompleted = false`, `CompletedDate = ""`).
    @MainActor public func makeJob() -> ShipJob {
        let j = ShipJob(jobNo: jobNo)
        j.title = title; j.workPlanNo = workPlanNo; j.status = status; j.classCode = classCode; j.category = category
        j.responsibleRank = responsibleRank; j.functionNo = functionNo; j.functionDescription = functionDescription
        j.interval = interval; j.dueStatus = dueStatus; j.dueDate = dueDate; j.finishedDate = finishedDate
        j.lastDoneDate = lastDoneDate; j.overdueDays = overdueDays; j.notify = notify; j.importedAt = importedAt
        return j
    }
}

public struct WorkOrderReadResult: Sendable {
    public var jobs: [WorkOrderDraft] = []
    /// VESSEL-318: formula cells in the used range without a saved result (rendered "").
    public var uncachedFormulaCount = 0
    public init() {}
}

/// The Shippalm "Work Order List" reader and AA's round-tripping writer (C# `ShippalmReader`).
public enum WorkOrderShippalmReader {
    public static let headerMissingMessage = "Could not find the Shippalm header row (expected 'No.' and 'Title')."

    /// The 16 AA-export headers in column order A → P (10 §4.4).
    public static let exportHeaders = [
        "No.", "Title", "Work Plan No.", "Work Order Status", "Class Code", "Work Order Category Code",
        "Responsible Rank", "Finished Date-Time", "Due Date", "Interval", "Function Description",
        "Due Status", "Function No.", "Last Done Date", "Overdue Days", "Notify",
    ]

    // MARK: Read (§3.4.1)

    /// Opens `url` (extension gate + package) and reads it; `now` stamps `ImportedAt` once per file
    /// (`yyyy-MM-dd HH:mm`, local); `today` resolves time-only / year-less date text (ExcelDate).
    public static func read(url: URL, now: NetDateTime, today: CivilDate, zone: TimeZone = .current) throws -> WorkOrderReadResult {
        let wb = try XlsxWorkbook.open(url)
        return try read(workbook: wb, now: now, today: today, zone: zone)
    }

    public static func read(workbook wb: XlsxWorkbook, now: NetDateTime, today: CivilDate,
                            zone: TimeZone = .current) throws -> WorkOrderReadResult {
        // VESSEL-304: the first worksheet with a used range, else the first worksheet; no used range → [].
        var sheet: XlsxWorksheet?
        for ref in wb.worksheets {
            let ws = try wb.load(ref)
            if ws.rangeUsed() != nil { sheet = ws; break }
        }
        if sheet == nil, let first = wb.worksheets.first { sheet = try wb.load(first) }
        var result = WorkOrderReadResult()
        guard let ws = sheet, let used = ws.rangeUsed() else { return result }

        func cell(_ r: Int, _ c: Int) throws -> String { try XlsxRender.shippalmCell(ws.cell(r, c), workbook: wb) }

        // Header row: within firstRow … firstRow+15, one cell "no." and another "title" (CrewText.Norm).
        var headerRow = -1
        for r in used.firstRow...min(used.lastRow, used.firstRow + 15) {
            var hasNo = false, hasTitle = false
            for c in used.firstColumn...used.lastColumn {
                let h = CrewText.norm(try cell(r, c))
                if h == "no." { hasNo = true } else if h == "title" { hasTitle = true }
            }
            if hasNo && hasTitle { headerRow = r; break }
        }
        guard headerRow >= 0 else { throw VesselReadError(headerMissingMessage) }

        // Column map: the FIRST column of each normalised header wins.
        var col: [String: Int] = [:]
        for c in used.firstColumn...used.lastColumn {
            let h = CrewText.norm(try cell(headerRow, c))
            if !h.isEmpty, col[h] == nil { col[h] = c }
        }
        func colOf(_ name: String) -> Int { col[CrewText.norm(name)] ?? -1 }
        let cNo = colOf("No."), cTitle = colOf("Title"), cPlan = colOf("Work Plan No."), cStatus = colOf("Work Order Status")
        let cClass = colOf("Class Code"), cCat = colOf("Work Order Category Code"), cRank = colOf("Responsible Rank")
        let cFnNo = colOf("Function No."), cFnDesc = colOf("Function Description"), cInterval = colOf("Interval")
        let cDueStatus = colOf("Due Status"), cDue = colOf("Due Date"), cFinished = colOf("Finished Date-Time")
        let cLastDone = colOf("Last Done Date"), cOverdue = colOf("Overdue Days"), cNotify = colOf("Notify")

        let imported = now.format(.isoMinute, zone: zone)
        if headerRow + 1 <= used.lastRow {
            for r in (headerRow + 1)...used.lastRow {
                func g(_ c: Int) throws -> String { try (c < 0 ? "" : cell(r, c)) }
                let no = NetText.trim(try g(cNo))
                if NetText.isBlank(no) { continue }
                var d = WorkOrderDraft(jobNo: no)
                d.title = try g(cTitle)
                d.workPlanNo = try g(cPlan)
                d.status = try g(cStatus)
                d.classCode = try g(cClass)
                d.category = try g(cCat)
                d.responsibleRank = try g(cRank)
                d.functionNo = try g(cFnNo)
                d.functionDescription = try g(cFnDesc)
                d.interval = try g(cInterval)
                d.dueStatus = try g(cDueStatus)
                d.dueDate = ShippalmDates.excelDate(try g(cDue), today: today)
                d.finishedDate = ShippalmDates.excelDate(try g(cFinished), today: today)
                d.lastDoneDate = ShippalmDates.excelDate(try g(cLastDone), today: today)
                d.overdueDays = parseOverdueDays(try g(cOverdue))
                d.notify = parseBool(try g(cNotify))
                d.importedAt = imported
                result.jobs.append(d)
            }
        }
        result.uncachedFormulaCount = ws.uncachedFormulaCount(in: used)
        return result
    }

    /// §3.4.3: trimmed; true iff OIC `yes`, `true`, `y`, or exactly `1`.
    public static func parseBool(_ s: String) -> Bool {
        let t = NetText.trim(s)
        return NetText.equalsIgnoreCase(t, "yes") || NetText.equalsIgnoreCase(t, "true") || t == "1"
            || NetText.equalsIgnoreCase(t, "y")
    }

    /// `int.TryParse(s, NumberStyles.Any, InvariantCulture)`; failure → 0. White space, a leading or trailing sign,
    /// parentheses, `¤`, `,` groups in the integer part, a `.` fraction of zeros only, and an exponent are accepted;
    /// a non-integral or out-of-`Int32` value fails.
    public static func parseOverdueDays(_ raw: String) -> Int {
        var s = raw.trimmingCharacters(in: CharacterSet(charactersIn: " \t\n\r\u{0B}\u{0C}"))
        guard !s.isEmpty else { return 0 }
        var negative = false
        if s.hasPrefix("("), s.hasSuffix(")"), s.count >= 2 { negative = true; s = String(s.dropFirst().dropLast()) }
        s = s.replacingOccurrences(of: "\u{00A4}", with: "")
        s = s.trimmingCharacters(in: CharacterSet(charactersIn: " \t\n\r\u{0B}\u{0C}"))
        if s.hasSuffix("-") { negative.toggle(); s.removeLast() } else if s.hasSuffix("+") { s.removeLast() }
        if s.hasPrefix("-") { negative.toggle(); s.removeFirst() } else if s.hasPrefix("+") { s.removeFirst() }
        let u = Array(s.utf8)
        guard let first = u.first, (0x30...0x39).contains(first) || first == 0x2E else { return 0 }
        var mantissa = "", i = 0, sawDot = false, digits = 0
        while i < u.count {
            let c = u[i]
            if (0x30...0x39).contains(c) { mantissa.append(Character(Unicode.Scalar(c))); digits += 1 }
            else if c == 0x2C, !sawDot { /* group separator */ }
            else if c == 0x2E, !sawDot { sawDot = true; mantissa.append(".") }
            else { break }
            i += 1
        }
        guard digits > 0 else { return 0 }
        var exponent = 0
        if i < u.count {
            guard u[i] == 0x65 || u[i] == 0x45 else { return 0 }
            i += 1
            var expNeg = false
            if i < u.count, u[i] == 0x2B || u[i] == 0x2D { expNeg = u[i] == 0x2D; i += 1 }
            var expDigits = 0
            while i < u.count, (0x30...0x39).contains(u[i]) {
                exponent = min(exponent * 10 + Int(u[i] - 0x30), 10_000); expDigits += 1; i += 1
            }
            guard expDigits > 0, i == u.count else { return 0 }
            if expNeg { exponent = -exponent }
        }
        guard var value = Decimal(string: mantissa, locale: Locale(identifier: "en_US_POSIX")) else { return 0 }
        if exponent != 0 {
            guard abs(exponent) <= 40 else { return 0 }
            var p = Decimal(1)
            for _ in 0..<abs(exponent) { p *= 10 }
            value = exponent > 0 ? value * p : value / p
        }
        if negative { value = -value }
        var rounded = Decimal()
        var v = value
        NSDecimalRound(&rounded, &v, 0, .plain)
        guard rounded == value else { return 0 }
        let n = NSDecimalNumber(decimal: rounded)
        guard n.compare(NSDecimalNumber(value: Int32.max)) != .orderedDescending,
              n.compare(NSDecimalNumber(value: Int32.min)) != .orderedAscending else { return 0 }
        return n.intValue
    }

    // MARK: Write (§3.4.2, §4.4)

    /// The export workbook of `jobs` in collection order (sheet `report`, bold header, I and N text, O numeric).
    @MainActor public static func exportSheet(_ jobs: [ShipJob]) -> XlsxSheetSpec {
        let rows: [[String]] = jobs.map { j in
            [j.jobNo, j.title, j.workPlanNo, j.status, j.classCode, j.category, j.responsibleRank, j.finishedDate,
             j.dueDate, j.interval, j.functionDescription, j.dueStatus, j.functionNo, j.lastDoneDate,
             String(j.overdueDays), j.notify ? "Yes" : "No"]
        }
        let cells: [[XlsxCellValue]] = zip(rows, jobs).map { row, j in
            row.enumerated().map { c, text in
                if c == 14 { return .number(Double(j.overdueDays)) }
                return text.isEmpty ? .empty : .text(text)
            }
        }
        let widths = autoFitWidths(header: exportHeaders, rows: rows)
        let columns = widths.enumerated().map { c, w in XlsxColumnSpec(width: w, textFormat: c == 8 || c == 13) }
        return XlsxSheetSpec(name: "report", columns: columns, boldHeader: true, header: exportHeaders, rows: cells)
    }

    /// Writes the export to `url` (overwrites).
    @MainActor public static func write(_ jobs: [ShipJob], to url: URL) throws {
        try XlsxWriter.write(to: url, sheet: exportSheet(jobs))
    }

    /// ClosedXML `AdjustToContents` approximation (10 §4.4): `max display characters × 1.1 + 2`, capped at 100.
    public static func autoFitWidths(header: [String], rows: [[String]]) -> [Double] {
        var maxChars = header.map { displayWidth($0) }
        for row in rows {
            for (c, text) in row.enumerated() where c < maxChars.count {
                maxChars[c] = max(maxChars[c], displayWidth(text))
            }
        }
        return maxChars.map { min(100, (Double($0) * 1.1 + 2).rounded(toPlaces: 2)) }
    }

    /// The longest line of `text`, in characters (grapheme clusters).
    static func displayWidth(_ text: String) -> Int {
        text.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "\n" || $0 == "\r\n" || $0 == "\r" })
            .map(\.count).max() ?? 0
    }
}

extension Double {
    /// Decimal rounding used for column widths (keeps the XML short).
    fileprivate func rounded(toPlaces p: Int) -> Double {
        var m = 1.0
        for _ in 0..<p { m *= 10 }
        return (self * m).rounded() / m
    }
}
