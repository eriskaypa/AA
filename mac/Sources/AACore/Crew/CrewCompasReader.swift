// Spec: 09 CREW-031, §3.3 (CompasReader.Read: sheet choice, header-row detection, cell → string), §4.9 (input
//       contract), §7.7; 10 §X.4.11 renderer A (`XlsxRender.compasCellString`, F2); ARCHITECTURE.md §6.5 (parsing runs
//       off-main over Sendable values).
import Foundation

/// One data row: normalised header → cell text (the right-most of duplicate headers wins).
public struct CrewCompasRow: Sendable, Equatable {
    public var values: [String: String]

    public init(values: [String: String] = [:]) { self.values = values }

    /// `Get(header)`: the value under `Norm(header)`, or `""`.
    public func get(_ header: String) -> String { values[CrewText.norm(header)] ?? "" }

    /// `Has(header)`: `Get` is not blank.
    public func has(_ header: String) -> Bool { !NetText.isBlank(get(header)) }
}

/// The rows of a COMPAS report plus what the importer needs to know about the workbook.
public struct CrewCompasSheet: Sendable, Equatable {
    public var sheetName: String
    public var headerRow: Int
    public var rows: [CrewCompasRow]
    public var use1904: Bool

    public init(sheetName: String = "", headerRow: Int = 0, rows: [CrewCompasRow] = [], use1904: Bool = false) {
        self.sheetName = sheetName; self.headerRow = headerRow; self.rows = rows; self.use1904 = use1904
    }
}

/// Import failures with the Windows texts (CREW-031) — shown as `Could not import the COMPAS file:\n\n{message}`.
public enum CrewImportError: Error, LocalizedError, Sendable, Equatable {
    case headerNotFound
    case workbook(XlsxReadError)

    public var errorDescription: String? {
        switch self {
        case .headerNotFound: return "Could not find the COMPAS header row (expected 'First name' and 'Surname')."
        case .workbook(let e): return e.errorDescription
        }
    }
}

public enum CrewCompasReader {
    /// Rows 1…20 are searched for the header row.
    public static let headerSearchRows = 20

    /// Opens and reads a COMPAS `.xlsx` (call off the main actor).
    public static func read(url: URL) throws(CrewImportError) -> CrewCompasSheet {
        let workbook: XlsxWorkbook
        do throws(XlsxReadError) { workbook = try XlsxWorkbook.open(url) } catch { throw .workbook(error) }
        return try read(workbook: workbook)
    }

    /// Worksheet `report` (any case) else the first; header row = first of rows 1…min(lastRow, 20) whose normalised
    /// cells contain both `first name` and `surname`; then every later row where First name or Surname is not blank.
    public static func read(workbook: XlsxWorkbook) throws(CrewImportError) -> CrewCompasSheet {
        guard let ref = workbook.worksheet(named: "report") ?? workbook.worksheets.first else {
            return CrewCompasSheet(use1904: workbook.use1904)
        }
        let sheet: XlsxWorksheet
        do throws(XlsxReadError) { sheet = try workbook.load(ref) } catch { throw .workbook(error) }
        guard let used = sheet.rangeUsed() else {
            return CrewCompasSheet(sheetName: ref.name, use1904: workbook.use1904)
        }
        let lastRow = used.lastRow, lastCol = used.lastColumn

        func cellString(_ r: Int, _ c: Int) throws(CrewImportError) -> String {
            do throws(XlsxReadError) { return try XlsxRender.compasCellString(sheet.cell(r, c), workbook: workbook) } catch { throw .workbook(error) }
        }

        var headerRow: Int?
        for r in 1...min(lastRow, headerSearchRows) {
            var names = Set<String>()
            for c in 1...lastCol { names.insert(CrewText.norm(try cellString(r, c))) }
            if names.contains("first name") && names.contains("surname") { headerRow = r; break }
        }
        guard let headerRow else { throw .headerNotFound }

        var headers: [(column: Int, name: String)] = []
        for c in 1...lastCol {
            let h = CrewText.norm(try cellString(headerRow, c))
            if !h.isEmpty { headers.append((c, h)) }
        }

        var rows: [CrewCompasRow] = []
        if headerRow < lastRow {
            for r in (headerRow + 1)...lastRow {
                var values: [String: String] = [:]
                for (c, h) in headers { values[h] = try cellString(r, c) }
                let row = CrewCompasRow(values: values)
                if row.has("First name") || row.has("Surname") { rows.append(row) }
            }
        }
        return CrewCompasSheet(sheetName: ref.name, headerRow: headerRow, rows: rows, use1904: workbook.use1904)
    }
}
