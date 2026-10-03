// Spec: 09 §I CREW-100…105, §3.9 (CrewColumns catalog, Defaults, Resolve, Cell, Pattern, LiteralSeparator;
//       CrewTableWindow BuildChoices / Persist), §3.10/§4.10 (XLSX via F1's `XlsxWriter`), §4.5 (Ui keys), §7.11/§7.12,
//       §8 Q10 (separator verbatim), Q11 (empty separator reloads as "-"); DECISIONS 09 Q4 (`CrewStoredDate`).
import Foundation

/// Table-view date format (persisted as its C# enum name in `UiState.CrewTableDateFormat`).
public enum CrewDateFormat: Int, Sendable, CaseIterable, Identifiable {
    case iso, dayMonthYear, monthDayYear, dayMonthName

    public var id: Int { rawValue }

    public var name: String {
        switch self {
        case .iso: return "Iso"
        case .dayMonthYear: return "DayMonthYear"
        case .monthDayYear: return "MonthDayYear"
        case .dayMonthName: return "DayMonthName"
        }
    }

    /// Combo labels (two spaces before the parenthesis).
    public var label: String {
        switch self {
        case .iso: return "2026-03-15  (Y-M-D)"
        case .dayMonthYear: return "15-03-2026  (D-M-Y)"
        case .monthDayYear: return "03-15-2026  (M-D-Y)"
        case .dayMonthName: return "15-Mar-2026  (D-Mon-Y)"
        }
    }

    /// `Enum.TryParse` of the stored name (invalid / null → Iso).
    public init(persisted text: String?) {
        guard let raw = text.map(NetText.trim), !raw.isEmpty else { self = .iso; return }
        if let f = CrewDateFormat.allCases.first(where: { $0.name == raw }) { self = f; return }
        if let n = Int(raw), let f = CrewDateFormat(rawValue: n) { self = f; return }
        self = .iso
    }
}

/// One catalog column.
public struct CrewColumn: Sendable, Hashable, Identifiable {
    public let key: String
    public let header: String
    public let isDate: Bool
    public var id: String { key }

    public init(key: String, header: String, isDate: Bool = false) {
        self.key = key; self.header = header; self.isDate = isDate
    }
}

/// A chooser row: a catalog column and whether it is ticked.
public struct CrewColumnChoice: Sendable, Hashable, Identifiable {
    public var column: CrewColumn
    public var shown: Bool
    public var id: String { column.key }
    public init(column: CrewColumn, shown: Bool) { self.column = column; self.shown = shown }
}

public enum CrewColumns {
    /// The 40-column catalog — order, keys, headers, date flag (09 §3.9).
    public static let all: [CrewColumn] = [
        CrewColumn(key: "LastName", header: "Last Name"),
        CrewColumn(key: "FirstName", header: "First Name"),
        CrewColumn(key: "MiddleName", header: "Middle Name"),
        CrewColumn(key: "FullName", header: "Full Name"),
        CrewColumn(key: "Cid", header: "CID"),
        CrewColumn(key: "Rank", header: "Rank"),
        CrewColumn(key: "RankCode", header: "Rank Code"),
        CrewColumn(key: "Nationality", header: "Nationality"),
        CrewColumn(key: "Gender", header: "Gender"),
        CrewColumn(key: "DateOfBirth", header: "Date of Birth", isDate: true),
        CrewColumn(key: "PlaceOfBirth", header: "Place of Birth"),
        CrewColumn(key: "Height", header: "Height"),
        CrewColumn(key: "EyesColor", header: "Eyes"),
        CrewColumn(key: "HairColor", header: "Hair"),
        CrewColumn(key: "UserType", header: "User Type"),
        CrewColumn(key: "SignedOnOff", header: "Signed On/Off"),
        CrewColumn(key: "Company", header: "Company"),
        CrewColumn(key: "Vessel", header: "Vessel"),
        CrewColumn(key: "SignOnDate", header: "Sign-On Date", isDate: true),
        CrewColumn(key: "SignOnPort", header: "Sign-On Port"),
        CrewColumn(key: "SignOffDate", header: "Sign-Off Date", isDate: true),
        CrewColumn(key: "SignOffPort", header: "Sign-Off Port"),
        CrewColumn(key: "DaysUntilSignOff", header: "Days to Sign-Off"),
        CrewColumn(key: "ContractStatus", header: "Contract Status"),
        CrewColumn(key: "PassportNumber", header: "Passport No."),
        CrewColumn(key: "PassportExpiry", header: "Passport Expiry", isDate: true),
        CrewColumn(key: "PassportIssued", header: "Passport Issued", isDate: true),
        CrewColumn(key: "SeamansBookNumber", header: "Seaman's Book No."),
        CrewColumn(key: "SeamansBookExpiry", header: "Seaman's Book Expiry", isDate: true),
        CrewColumn(key: "SeamansBookIssued", header: "Seaman's Book Issued", isDate: true),
        CrewColumn(key: "CocNumber", header: "CoC No."),
        CrewColumn(key: "CocExpiry", header: "CoC Expiry", isDate: true),
        CrewColumn(key: "CocIssue", header: "CoC Issue", isDate: true),
        CrewColumn(key: "HealthCertExpiry", header: "Health Cert Expiry", isDate: true),
        CrewColumn(key: "NokFirstName", header: "Next of Kin (First)"),
        CrewColumn(key: "NokLastName", header: "Next of Kin (Last)"),
        CrewColumn(key: "NokRelationship", header: "Next of Kin (Relation)"),
        CrewColumn(key: "ChecklistCount", header: "Checklist Items"),
        CrewColumn(key: "ImportedAt", header: "Imported At"),
        CrewColumn(key: "SourceFile", header: "Source File"),
    ]

    public static let defaultKeys = ["LastName", "FirstName", "Cid", "Rank", "Nationality", "DateOfBirth",
                                     "SignOnDate", "SignOffDate", "ContractStatus"]

    static let byKey: [String: CrewColumn] = Dictionary(uniqueKeysWithValues: all.map { ($0.key, $0) })

    public static func column(_ key: String) -> CrewColumn? { byKey[key] }

    /// `Resolve(keys)`: known keys in order (unknown dropped); empty → the defaults.
    public static func resolve(_ keys: [String]) -> [CrewColumn] {
        let cols = keys.compactMap { byKey[$0] }
        return cols.isEmpty ? defaultKeys.compactMap { byKey[$0] } : cols
    }

    /// `BuildChoices` (CREW-102): never configured → the nine defaults ticked in default order, then every other
    /// column unticked in catalog order; else the saved order (unknown keys dropped, duplicates ignored) with ticks
    /// from `shown`, then catalog columns missing from the saved order appended unticked.
    public static func buildChoices(order: [String], shown: [String]) -> [CrewColumnChoice] {
        var out: [CrewColumnChoice] = []
        var seen = Set<String>()
        if order.isEmpty {
            for k in defaultKeys { if let c = byKey[k], seen.insert(k).inserted { out.append(CrewColumnChoice(column: c, shown: true)) } }
        } else {
            let ticked = Set(shown)
            for k in order {
                guard let c = byKey[k], seen.insert(k).inserted else { continue }
                out.append(CrewColumnChoice(column: c, shown: ticked.contains(k)))
            }
        }
        for c in all where seen.insert(c.key).inserted { out.append(CrewColumnChoice(column: c, shown: false)) }
        return out
    }

    /// CREW-104 persisted values: every key in chooser order, the ticked keys in order.
    public static func persistedLists(_ choices: [CrewColumnChoice]) -> (order: [String], shown: [String]) {
        (choices.map(\.column.key), choices.filter(\.shown).map(\.column.key))
    }

    /// The separator as loaded (`IsNullOrEmpty` → `-`, CREW-101 / §8 Q11).
    public static func loadedSeparator(_ stored: String?) -> String {
        guard let s = stored, !s.isEmpty else { return "-" }
        return s
    }

    /// The separator box holds at most three characters (CREW-101).
    public static func clampSeparator(_ s: String) -> String { String(s.prefix(3)) }

    /// The raw value of a column for one member (`DaysUntilSignOff` and `ContractStatus` use `today`).
    @MainActor public static func value(_ col: CrewColumn, _ m: CrewMember, today: CivilDate) -> String {
        switch col.key {
        case "FullName": return m.fullName
        case "Cid": return m.employeeId
        case "EyesColor": return m.eyesColor
        case "HairColor": return m.hairColor
        case "DaysUntilSignOff": return CrewStoredDate.daysUntilSignOff(m, today: today).map { String($0) } ?? ""
        case "ContractStatus": return CrewStoredDate.contractStatus(m, today: today).name
        case "ChecklistCount": return String(m.checklist.count)
        case "ImportedAt": return m.importedAt
        case "SourceFile": return m.sourceFile
        default: return m.stringField(col.key)
        }
    }

    /// `Cell(col, m, fmt, sep)`: non-date column or empty → raw; unparseable date → raw verbatim; else formatted.
    @MainActor public static func cell(_ col: CrewColumn, _ m: CrewMember, format: CrewDateFormat, separator: String,
                                       today: CivilDate) -> String {
        let raw = value(col, m, today: today)
        guard col.isDate, !raw.isEmpty, let d = CrewStoredDate.civil(raw) else { return raw }
        return formatDate(d, format: format, separator: separator)
    }

    /// The date built from components with the separator verbatim (09 §3.9 Swift note; §8 Q10).
    public static func formatDate(_ d: CivilDate, format: CrewDateFormat, separator s: String) -> String {
        let yyyy = CivilDate.pad(d.year, 4), mm = CivilDate.pad(d.month, 2), dd = CivilDate.pad(d.day, 2)
        switch format {
        case .dayMonthYear: return dd + s + mm + s + yyyy
        case .monthDayYear: return mm + s + dd + s + yyyy
        case .dayMonthName: return dd + s + CrewDateResolver.monthAbbrevs[d.month - 1] + s + yyyy
        case .iso: return yyyy + s + mm + s + dd
        }
    }

    /// `Pattern(fmt, sep)` — the .NET custom format string (documentation and parity tests only; never fed to a
    /// formatter): `LiteralSeparator` = `-` for nil, `""` for empty, else `'sep'` with `'` → `\'`.
    public static func pattern(_ format: CrewDateFormat, separator: String?) -> String {
        let s: String
        if let sep = separator {
            s = sep.isEmpty ? "" : "'" + sep.replacingOccurrences(of: "'", with: "\\'") + "'"
        } else {
            s = "-"
        }
        switch format {
        case .dayMonthYear: return "dd\(s)MM\(s)yyyy"
        case .monthDayYear: return "MM\(s)dd\(s)yyyy"
        case .dayMonthName: return "dd\(s)MMM\(s)yyyy"
        case .iso: return "yyyy\(s)MM\(s)dd"
        }
    }

    /// The table rows (one string per shown column) in the given member order.
    @MainActor public static func rows(_ crew: [CrewMember], columns: [CrewColumn], format: CrewDateFormat,
                                       separator: String, today: CivilDate) -> [[String]] {
        crew.map { m in columns.map { cell($0, m, format: format, separator: separator, today: today) } }
    }

    /// `"{crewCount} crew  ·  {k} column(s)"` (CREW-101).
    public static func countText(crew: Int, columns k: Int) -> String {
        "\(crew) crew  \u{00B7}  \(k) column" + (k == 1 ? "" : "s")
    }

    /// `crew-{local today yyyy-MM-dd}.xlsx` (CREW-105).
    public static func exportFileName(today: CivilDate) -> String { "crew-\(today.iso).xlsx" }

    /// CREW-105: the shown columns/order/formatting to one `Crew` sheet (F1's writer, 09 §3.10/§4.10 bytes).
    public static func export(to url: URL, headers: [String], rows: [[String]]) throws {
        try XlsxWriter.write(to: url, sheetName: "Crew", headers: headers, rows: rows)
    }

    /// `Exported {n} crew to:\n{path}\n\nOpen it now?`.
    public static func exportedMessage(count: Int, path: String) -> String {
        "Exported \(count) crew to:\n\(path)\n\nOpen it now?"
    }
}
