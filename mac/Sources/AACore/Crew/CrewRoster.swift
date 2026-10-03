// Spec: 09 §B CREW-010…018 (roster: search, expiring filter, rows, status line, selection), §C CREW-020…026 (read-only
//       card: header, contract banner, checklist summary, six detail sections, review notes, provenance), §F CREW-060/061
//       texts, §3.7, §7.8, §7.10; DECISIONS 09 (Clear all = one Trash batch). Pure text/model helpers so every string is
//       unit-tested; the views only lay them out.
import Foundation

/// One roster row (CREW-013).
public struct CrewRosterRow: Sendable, Identifiable, Equatable {
    public var id: UUID
    public var key: String
    public var name: String
    public var sub: String
    public var expiryText: String
    public var tone: CrewExpiryTone
    public var flagCount: Int

    public init(id: UUID, key: String, name: String, sub: String, expiryText: String, tone: CrewExpiryTone, flagCount: Int) {
        self.id = id; self.key = key; self.name = name; self.sub = sub; self.expiryText = expiryText; self.tone = tone
        self.flagCount = flagCount
    }
}

/// One label/value row of a card section.
public struct CrewCardField: Sendable, Equatable, Identifiable {
    public var id: Int
    public var label: String
    /// The raw value (may be blank).
    public var value: String
    /// What the card shows: the value, or `—` (U+2014) when blank.
    public var display: String { NetText.isBlank(value) ? "\u{2014}" : value }

    public init(id: Int, label: String, value: String) { self.id = id; self.label = label; self.value = value }
}

/// One of the six bordered detail sections (CREW-023).
public struct CrewCardSection: Sendable, Equatable, Identifiable {
    public var id: String { title }
    public var glyph: String
    public var title: String
    public var fields: [CrewCardField]

    /// `"{glyph}  {title}"` (two spaces).
    public var header: String { "\(glyph)  \(title)" }

    public init(glyph: String, title: String, fields: [CrewCardField]) {
        self.glyph = glyph; self.title = title; self.fields = fields
    }
}

public enum CrewRoster {
    public static let searchPrompt = "Search name / rank / nationality / ID..."
    public static let unnamed = "(unnamed)"
    public static let separator = "   \u{00B7}   "

    // MARK: Filter (CREW-012 / CREW-014)

    /// Search (trimmed query; FullName, Rank, Nationality, EmployeeId; ordinal ignore-case) then the expiring filter.
    @MainActor public static func filter(_ crew: [CrewMember], query: String, expiringOnly: Bool,
                                         today: CivilDate) -> [CrewMember] {
        let q = NetText.trim(query)
        var out = crew
        if !q.isEmpty {
            out = out.filter { c in
                NetText.containsIgnoreCase(c.fullName, q) || NetText.containsIgnoreCase(c.rank, q)
                    || NetText.containsIgnoreCase(c.nationality, q) || NetText.containsIgnoreCase(c.employeeId, q)
            }
        }
        if expiringOnly {
            out = out.filter { c in
                guard let d = CrewStoredDate.daysUntilSignOff(c, today: today) else { return false }
                return d <= CrewExpiry.warnDays
            }
        }
        return out
    }

    /// Filter, then sort by the roster's mode, then build the rows.
    @MainActor public static func rows(_ crew: [CrewMember], query: String, expiringOnly: Bool, mode: CrewSortMode,
                                       today: CivilDate) -> [CrewRosterRow] {
        CrewSort.sorted(filter(crew, query: query, expiringOnly: expiringOnly, today: today), mode: mode, today: today)
            .map { row($0, today: today) }
    }

    @MainActor public static func row(_ m: CrewMember, today: CivilDate) -> CrewRosterRow {
        let e = CrewExpiry.expiry(m, today: today)
        return CrewRosterRow(id: m.id, key: m.key, name: displayName(m), sub: subLine(m), expiryText: e.text, tone: e.tone,
                             flagCount: m.flags.count)
    }

    /// FullName or `(unnamed)`.
    @MainActor public static func displayName(_ m: CrewMember) -> String {
        let n = m.fullName
        return n.isEmpty ? unnamed : n
    }

    /// RankDisplay, Nationality, Vessel — blanks skipped — joined by `"   ·   "`.
    @MainActor public static func subtitle(_ m: CrewMember) -> String {
        [CrewExpiry.rankDisplay(m), m.nationality, m.vessel].filter { !NetText.isBlank($0) }.joined(separator: separator)
    }

    /// The subtitle + `"   ⚑ {flagCount}"` when the member has review flags.
    @MainActor public static func subLine(_ m: CrewMember) -> String {
        subtitle(m) + (m.hasFlags ? "   \u{2691} \(m.flags.count)" : "")
    }

    // MARK: Selection (CREW-017)

    /// The row to select after a refresh: the first row with the remembered key, else the first row, else none.
    public static func selection(after rows: [CrewRosterRow], keepKey: String?) -> UUID? {
        if let keepKey, let r = rows.first(where: { Ordinal.equals($0.key, keepKey) }) { return r.id }
        return rows.first?.id
    }

    /// CREW-005: the row for a navigated member — by id, else the first with the member's key.
    public static func selection(for memberID: UUID, key: String?, in rows: [CrewRosterRow]) -> UUID? {
        if let r = rows.first(where: { $0.id == memberID }) { return r.id }
        if let key, let r = rows.first(where: { Ordinal.equals($0.key, key) }) { return r.id }
        return nil
    }

    // MARK: Status line (CREW-016)

    public static let emptyStatus = "No crew yet — click \u{201C}Import COMPAS...\u{201D} to load a crew report."

    /// Counts the **whole** roster, never the filtered view.
    public static func statusLine(total: Int, expiring: Int) -> String {
        if total == 0 { return emptyStatus }
        return "\(total) crew" + (expiring > 0 ? "  \u{00B7}  \u{26A0} \(expiring) contract(s) expiring \u{2264}\(CrewExpiry.warnDays)d" : "")
    }

    // MARK: Card (CREW-020…025)

    /// `PortDisplay(code, raw)`.
    public static func portDisplay(code: String, raw: String) -> String {
        if NetText.isBlank(code) && NetText.isBlank(raw) { return "" }
        if NetText.isBlank(raw) || Ordinal.equals(raw, code) { return code }
        return "\(code)   (COMPAS: \(raw))"
    }

    /// Nationality + `"   (COMPAS: {RawNationality})"` when the raw text is non-blank and differs.
    @MainActor public static func nationalityDisplay(_ m: CrewMember) -> String {
        m.nationality + (NetText.isBlank(m.rawNationality) || Ordinal.equals(m.rawNationality, m.nationality)
            ? "" : "   (COMPAS: \(m.rawNationality))")
    }

    /// The six detail sections in order.
    @MainActor public static func sections(_ m: CrewMember) -> [CrewCardSection] {
        func s(_ glyph: String, _ title: String, _ rows: [(String, String)]) -> CrewCardSection {
            CrewCardSection(glyph: glyph, title: title,
                            fields: rows.enumerated().map { CrewCardField(id: $0.offset, label: $0.element.0, value: $0.element.1) })
        }
        return [
            s("\u{1FAAA}", "Identity", [
                ("First name", m.firstName), ("Middle name", m.middleName), ("Last name", m.lastName),
                ("Employee ID", m.employeeId), ("Nationality", nationalityDisplay(m)), ("Date of birth", m.dateOfBirth),
                ("Place of birth", m.placeOfBirth), ("Gender", m.gender),
            ]),
            s("\u{2693}", "Employment & Sign-On / Sign-Off", [
                ("Rank", CrewExpiry.rankDisplay(m)), ("User type", m.userType), ("Status", m.signedOnOff),
                ("Company", m.company), ("Vessel", m.vessel), ("Sign-on date", m.signOnDate),
                ("Sign-on port", portDisplay(code: m.signOnPort, raw: m.signOnPortRaw)), ("Sign-off date", m.signOffDate),
                ("Sign-off port", portDisplay(code: m.signOffPort, raw: m.signOffPortRaw)),
            ]),
            s("\u{1F6C2}", "Travel Documents", [
                ("Passport no.", m.passportNumber), ("Passport issued", m.passportIssued),
                ("Passport expiry", m.passportExpiry), ("Seaman's book no.", m.seamansBookNumber),
                ("Seaman's book issued", m.seamansBookIssued), ("Seaman's book expiry", m.seamansBookExpiry),
            ]),
            s("\u{1F4DC}", "Certificates & Medical", [
                ("CoC number", m.cocNumber), ("CoC issued", m.cocIssue), ("CoC expiry", m.cocExpiry),
                ("Health cert. expiry", m.healthCertExpiry),
            ]),
            s("\u{1F4CF}", "Physical", [("Height (cm)", m.height), ("Eyes", m.eyesColor), ("Hair", m.hairColor)]),
            s("\u{1F465}", "Next of Kin", [
                ("First name", m.nokFirstName), ("Last name", m.nokLastName), ("Relationship", m.nokRelationship),
            ]),
        ]
    }

    /// CREW-022 checklist summary line.
    @MainActor public static func checklistSummary(_ m: CrewMember) -> String {
        let total = m.checklist.count
        if total == 0 { return "No items yet — open to add tasks (each can have a due date)." }
        let done = m.checklist.filter(\.done).count
        var next: ChecklistStep?
        for s in m.checklist where !s.done {
            guard let d = s.deadline else { continue }
            if let n = next, let nd = n.deadline, nd.ticks <= d.ticks { continue }
            next = s
        }
        var line = "\(total) item(s), \(done) done"
        if let next, let d = next.deadline {
            line += "   \u{00B7}   next due \(d.format(.isoDate)) — \(shorten(next.title, 40))"
        }
        return line
    }

    /// More than `limit` UTF-16 units → the first `limit − 1` + `…`.
    public static func shorten(_ s: String, _ limit: Int) -> String {
        let u = Array(s.utf16)
        guard u.count > limit else { return s }
        return String(decoding: u[0..<(limit - 1)], as: UTF16.self) + "\u{2026}"
    }

    /// CREW-024 `"⚑ Review notes ({count})"`.
    public static func reviewNotesTitle(_ count: Int) -> String { "\u{2691} Review notes (\(count))" }

    /// `"{Field}: {Message}"` (date flags therefore show a doubled prefix — faithful, 09 §8 Q12).
    public static func flagLine(_ f: CrewReviewFlag) -> String { "\(f.field): \(f.message)" }

    /// CREW-025 provenance footer, or nil when both stamps are blank.
    @MainActor public static func provenance(_ m: CrewMember) -> String? {
        if NetText.isBlank(m.importedAt) && NetText.isBlank(m.sourceFile) { return nil }
        return "Imported \(m.importedAt)" + (NetText.isBlank(m.sourceFile) ? "" : " from \(m.sourceFile)")
    }

    // MARK: Delete / clear (CREW-060 / CREW-061, DECISIONS 09)

    public static let deleteTitle = "Confirm"

    /// The Windows text with the Mac key rendering (09 §6.4: "Ctrl+Z" → "⌘Z").
    @MainActor public static func deleteMessage(_ m: CrewMember) -> String {
        "Move \(m.fullName) to the Trash?\n\nYou can restore them from File \u{25B8} Trash, or undo with \u{2318}Z."
    }

    public static let clearTitle = "Confirm clear"

    /// "Remove ALL crew from the roster?" + the Mac note that the batch goes to the Trash (DECISIONS 09).
    public static func clearMessage(count: Int) -> String {
        "Remove ALL crew from the roster?\n\nAll \(count) member(s) go to the Trash as one batch — restore them from File \u{25B8} Trash, or undo with \u{2318}Z."
    }

    public static let tableEmptyTitle = "Table view"
    public static let tableEmptyMessage = "No crew yet — import a COMPAS report first."
}
