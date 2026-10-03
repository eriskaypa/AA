// Spec: 09 CREW-034, §3.5 (CrewConverter: field order, flags, DeriveMiddle, SplitName, MapPort, FmtDate,
//       DateSummary), §4.2/§4.3, §7.5/§7.6; DECISIONS 09 Q2 (summary when the user overrode a conflicted file).
//       ARCHITECTURE.md §2.2 (conversion is a pure value step; the apply step that builds `CrewMember`s is main-actor).
import Foundation

/// One converted COMPAS row — every persisted string of `CrewMember` plus its review flags (Sendable, so the whole
/// conversion can run off the main actor; `makeMember` builds the model object on the main actor).
public struct CrewRecord: Sendable, Equatable {
    public var employeeId = "", firstName = "", middleName = "", lastName = "", nationality = "", dateOfBirth = ""
    public var placeOfBirth = "", gender = "", height = "", eyesColor = "", hairColor = ""
    public var userType = "Crew", rank = "", rankCode = "", signedOnOff = "On", company = "", vessel = ""
    public var signOnDate = "", signOnPort = "", signOnPortRaw = "", signOffDate = "", signOffPort = ""
    public var signOffPortRaw = "", passportNumber = "", passportExpiry = "", passportIssued = ""
    public var seamansBookNumber = "", seamansBookExpiry = "", seamansBookIssued = "", cocNumber = "", cocExpiry = ""
    public var cocIssue = "", healthCertExpiry = "", nokFirstName = "", nokLastName = "", nokRelationship = ""
    public var rawNationality = ""
    public var flags: [CrewReviewFlag] = []
    public var importedAt = "", sourceFile = ""

    public init() {}

    /// `CrewMember.Key` of the converted member: EmployeeId if not blank, else `"{First}|{Last}".Trim('|')`.
    public var key: String {
        if !NetText.isBlank(employeeId) { return employeeId }
        return NetText.trim("\(firstName)|\(lastName)", characters: [0x7C])
    }

    /// A new `CrewMember` (empty Checklist / Schedule) carrying these values.
    @MainActor public func makeMember(id: UUID = UUID()) -> CrewMember {
        let m = CrewMember(id: id)
        m.employeeId = employeeId; m.firstName = firstName; m.middleName = middleName; m.lastName = lastName
        m.nationality = nationality; m.dateOfBirth = dateOfBirth; m.placeOfBirth = placeOfBirth; m.gender = gender
        m.height = height; m.eyesColor = eyesColor; m.hairColor = hairColor; m.userType = userType; m.rank = rank
        m.rankCode = rankCode; m.signedOnOff = signedOnOff; m.company = company; m.vessel = vessel
        m.signOnDate = signOnDate; m.signOnPort = signOnPort; m.signOnPortRaw = signOnPortRaw
        m.signOffDate = signOffDate; m.signOffPort = signOffPort; m.signOffPortRaw = signOffPortRaw
        m.passportNumber = passportNumber; m.passportExpiry = passportExpiry; m.passportIssued = passportIssued
        m.seamansBookNumber = seamansBookNumber; m.seamansBookExpiry = seamansBookExpiry
        m.seamansBookIssued = seamansBookIssued; m.cocNumber = cocNumber; m.cocExpiry = cocExpiry; m.cocIssue = cocIssue
        m.healthCertExpiry = healthCertExpiry; m.nokFirstName = nokFirstName; m.nokLastName = nokLastName
        m.nokRelationship = nokRelationship; m.rawNationality = rawNationality; m.flags = flags
        m.importedAt = importedAt; m.sourceFile = sourceFile
        return m
    }
}

/// The ten COMPAS date columns observed for the dd/mm inference, with their roles (09 §3.5 `DateColumns`).
public enum CrewDateColumns {
    public static let all: [(header: String, role: CrewDateRole)] = [
        ("Date of Birth", .pastOnly), ("Joining Date", .any), ("Sign Off Date", .futureLikely),
        ("Passport Expiry Date", .futureLikely), ("Passport Issued Date", .pastOnly),
        ("Seaman Book Expiry Date", .futureLikely), ("Seaman Book Issue Date", .pastOnly),
        ("Licence Expiry Date", .futureLikely), ("Licence Issue Date", .pastOnly),
        ("Medical Examination Expiry", .futureLikely),
    ]
}

/// COMPAS row → crew card values + review notes. Owns the file-wide `CrewDateResolver`.
public struct CrewConverter: Sendable {
    public let sourceFile: String
    public let importedAt: String
    public var dates: CrewDateResolver
    public private(set) var unreadableDates = 0
    /// Computed and never displayed (09 §8 Q17) — kept for parity and tests.
    public private(set) var orderDependentDates = 0

    /// `importedAt` = local now `yyyy-MM-dd HH:mm` (one stamp for the whole import).
    public init(sourceFile: String, now: NetDateTime, today: CivilDate, zone: TimeZone = .current, use1904: Bool = false) {
        self.sourceFile = sourceFile
        self.importedAt = now.format(.isoMinute)
        self.dates = CrewDateResolver(today: today, zone: zone, use1904: use1904)
    }

    public var dateOrder: CrewDateOrder { dates.order }
    public var dateEvidence: Int { dates.decisiveCount }

    /// `LearnDateFormat`: observe every value of the ten date columns of every row, then infer.
    public mutating func learnDateFormat(_ rows: [CrewCompasRow], fallback: CrewDateOrder = .unknown) {
        for row in rows {
            for col in CrewDateColumns.all { dates.observe(row.get(col.header)) }
        }
        dates.infer(fallback: fallback)
    }

    /// The user's answer to the date-order question: re-infer with it as the fallback (Unknown files) or adopt it
    /// outright (Conflicted files, DECISIONS 09 Q2).
    public mutating func applyAnswer(_ order: CrewDateOrder) {
        dates.adopt(order, byUser: true)
    }

    /// `DateSummary()`.
    public func dateSummary() -> String {
        let n = dates.decisiveCount
        let values = "\(n) value" + (n == 1 ? "" : "s")
        let how: String
        switch dates.order {
        case .dayFirst where dates.conflictOverridden:
            how = "day first (dd/mm) as chosen at import, although this file writes dates BOTH ways"
        case .monthFirst where dates.conflictOverridden:
            how = "month first (mm/dd) as chosen at import, although this file writes dates BOTH ways"
        case .dayFirst: how = "day first (dd/mm), proved by \(values)"
        case .monthFirst: how = "month first (mm/dd), proved by \(values)"
        case .conflicted: how = "inconsistently — this file writes dates BOTH ways, so ambiguous ones were left unread"
        case .unknown: how = "in unambiguous formats only; nothing in the file said whether 03/04 means 3 April or 4 March"
        }
        let tail = unreadableDates > 0 ? ", \(unreadableDates) could not be read" : ""
        return "dates read " + how + tail
    }

    // MARK: Convert

    /// `Convert(row)` — field by field in the 09 §3.5 order (flags are appended in this order).
    public mutating func convert(_ row: CrewCompasRow) -> CrewRecord {
        var m = CrewRecord()
        m.sourceFile = sourceFile
        m.importedAt = importedAt
        var flags: [CrewReviewFlag] = []

        m.firstName = row.get("First name")
        m.lastName = row.get("Surname")
        m.middleName = Self.deriveMiddle(row)
        m.employeeId = [row.get("Code"), row.get("CMS ID Number"), row.get("Passport Number")]
            .first { !NetText.isBlank($0) } ?? ""

        let code = NetText.toUpperInvariant(NetText.trim(row.get("Nationality code")))
        let demonym = CrewText.norm(row.get("Nationality"))
        if let c = CrewMappingTables.country(forISO3: code) {
            m.nationality = c
        } else if let c = CrewMappingTables.country(forDemonym: demonym) {
            m.nationality = c
        } else {
            m.nationality = row.get("Nationality")
        }
        m.rawNationality = row.get("Nationality")

        m.dateOfBirth = fmtDate(row.get("Date of Birth"), "Date of birth", .pastOnly, &flags)
        m.placeOfBirth = row.get("Place of Birth")
        let g = NetText.toUpperInvariant(NetText.trim(row.get("Gender")))
        m.gender = CrewMappingTables.gender(for: g) ?? ""
        if !g.isEmpty && m.gender.isEmpty {
            flags.append(CrewReviewFlag(severity: .info, field: "Gender", message: "Gender code '\(g)' not recognised."))
        }
        m.height = row.get("Height")
        m.eyesColor = row.get("Eyes Colour")
        m.hairColor = row.get("Hair Colour")

        m.userType = "Crew"
        m.signedOnOff = "On"
        m.company = row.get("Source")
        m.vessel = row.get("Last Vessel")

        let raw = NetText.toUpperInvariant(NetText.trim(row.get("Rank")))
        m.rankCode = raw
        if let rm = CrewMappingTables.rank(for: raw) {
            m.rank = rm.dnv
            if rm.approximate {
                flags.append(CrewReviewFlag(severity: .warning, field: "Rank",
                                            message: "Rank code '\(raw)' → '\(rm.dnv)' (approximate — verify)."))
            }
        } else if !raw.isEmpty {
            m.rank = "Other"
            flags.append(CrewReviewFlag(severity: .warning, field: "Rank",
                                        message: "Unknown rank code '\(raw)' → 'Other' (set manually)."))
        } else {
            m.rank = "Other"
            flags.append(CrewReviewFlag(severity: .error, field: "Rank",
                                        message: "No rank in COMPAS → 'Other' (mandatory, set manually)."))
        }

        m.signOnDate = fmtDate(row.get("Joining Date"), "Sign-on date", .any, &flags)
        m.signOnPortRaw = row.get("Joining Port")
        m.signOnPort = Self.mapPort(m.signOnPortRaw, field: "Sign-on port", &flags)

        m.signOffDate = fmtDate(row.get("Sign Off Date"), "Sign-off date", .futureLikely, &flags)
        m.signOffPortRaw = row.get("SignOff Port")
        if !NetText.isBlank(m.signOffPortRaw) {
            m.signOffPort = Self.mapPort(m.signOffPortRaw, field: "Sign-off port", &flags)
        }
        if NetText.isBlank(m.signOffDate) {
            flags.append(CrewReviewFlag(severity: .info, field: "Sign-off date",
                                        message: "No sign-off date in COMPAS — contract expiry can't be tracked until it's filled in."))
        }

        m.passportNumber = row.get("Passport Number")
        m.passportExpiry = fmtDate(row.get("Passport Expiry Date"), "Passport expiry", .futureLikely, &flags)
        m.passportIssued = fmtDate(row.get("Passport Issued Date"), "Passport issued", .pastOnly, &flags)

        m.seamansBookNumber = row.get("Seaman Book Number")
        m.seamansBookExpiry = fmtDate(row.get("Seaman Book Expiry Date"), "Seaman's book expiry", .futureLikely, &flags)
        m.seamansBookIssued = fmtDate(row.get("Seaman Book Issue Date"), "Seaman's book issued", .pastOnly, &flags)

        if row.has("Licence Number") {
            m.cocNumber = row.get("Licence Number")
            m.cocExpiry = fmtDate(row.get("Licence Expiry Date"), "CoC expiry", .futureLikely, &flags)
            m.cocIssue = fmtDate(row.get("Licence Issue Date"), "CoC issue", .pastOnly, &flags)
        }
        m.healthCertExpiry = fmtDate(row.get("Medical Examination Expiry"), "Health cert. expiry", .futureLikely, &flags)

        let nok = Self.splitName(row.get("Next of Kin - Name"))
        m.nokFirstName = nok.first
        m.nokLastName = nok.last
        let grade = CrewText.norm(row.get("Next of Kin - Grade"))
        if !grade.isEmpty {
            m.nokRelationship = CrewMappingTables.relationship(forNormalised: grade) ?? "Other"
            if m.nokRelationship == "Other" && grade != "not specified" {
                flags.append(CrewReviewFlag(severity: .info, field: "Next of kin", message: "Relationship '\(grade)' → 'Other'."))
            }
        }

        for (value, label) in [(m.firstName, "First name"), (m.lastName, "Last name"), (m.employeeId, "Employee ID"),
                               (m.rank, "Rank"), (m.signOnDate, "Sign-on date"), (m.signOnPort, "Sign-on port")]
        where NetText.isBlank(value) {
            flags.append(CrewReviewFlag(severity: .error, field: label,
                                        message: "Mandatory field '\(label)' is empty — missing in COMPAS, fill manually."))
        }
        m.flags = flags
        return m
    }

    /// `FmtDate`: unreadable non-empty text → Error flag, text kept; an order-dependent reading → Warning; else
    /// `yyyy-MM-dd`.
    mutating func fmtDate(_ value: String, _ field: String, _ role: CrewDateRole, _ flags: inout [CrewReviewFlag]) -> String {
        let r = dates.resolve(value, role: role)
        guard let date = r.value else {
            if !r.raw.isEmpty {
                unreadableDates += 1
                let why = r.note ?? "could not read '\(r.raw)'"
                flags.append(CrewReviewFlag(severity: .error, field: field,
                                            message: "\(field): \(why) — left as-is, set it by hand."))
            }
            return r.raw
        }
        if r.dependedOnOrder {
            orderDependentDates += 1
            flags.append(CrewReviewFlag(severity: .warning, field: field, message: "\(field): \(r.note ?? "")"))
        }
        return date.iso
    }

    // MARK: Helpers

    /// .NET `Regex("\s+").Replace(s, " ")`.
    static func collapseWhitespace(_ s: String) -> String {
        var out: [UInt16] = []
        var inSpace = false
        for u in s.utf16 {
            if NetText.isWhiteSpace(u) {
                if !inSpace { out.append(0x20); inSpace = true }
            } else { out.append(u); inSpace = false }
        }
        return String(decoding: out, as: UTF16.self)
    }

    /// `DeriveMiddle`: the explicit "Original middle name" unless blank or `-`; else the part of `Name` after
    /// `First name` (ordinal ignore-case prefix, no word-boundary check), trimmed of spaces and dashes.
    public static func deriveMiddle(_ row: CrewCompasRow) -> String {
        let explicit = NetText.trim(row.get("Original middle name"))
        if !explicit.isEmpty && explicit != "-" { return explicit }
        let name = collapseWhitespace(NetText.trim(row.get("Name")))
        let first = collapseWhitespace(NetText.trim(row.get("First name")))
        let nu = Array(name.utf16), fu = Array(first.utf16)
        guard !nu.isEmpty, !fu.isEmpty, fu.count <= nu.count,
              NetText.equalsIgnoreCase(String(decoding: nu[0..<fu.count], as: UTF16.self), first) else { return "" }
        let rest = String(decoding: nu[fu.count...], as: UTF16.self)
        return NetText.trim(NetText.trim(rest, characters: [0x20, 0x2D]))
    }

    /// `SplitName`: blank → ("", ""); one word → (word, ""); else (all but the last word, last word).
    public static func splitName(_ full: String) -> (first: String, last: String) {
        if NetText.isBlank(full) { return ("", "") }
        let parts = collapseWhitespace(NetText.trim(full)).components(separatedBy: " ")
        if parts.count == 1 { return (parts[0], "") }
        return (parts.dropLast().joined(separator: " "), parts[parts.count - 1])
    }

    /// `MapPort`: blank → "" (no flag); table hit → UN/LOCODE (+ Warning when Verify); miss → Warning and the
    /// original value.
    static func mapPort(_ value: String, field: String, _ flags: inout [CrewReviewFlag]) -> String {
        if NetText.isBlank(value) { return "" }
        if let pm = CrewMappingTables.port(forNormalised: CrewText.norm(value)) {
            if pm.verify {
                flags.append(CrewReviewFlag(severity: .warning, field: field,
                                            message: "Port '\(value)' → \(pm.unlocode) (UN/LOCODE best-guess — verify)."))
            }
            return pm.unlocode
        }
        flags.append(CrewReviewFlag(severity: .warning, field: field,
                                    message: "Port '\(value)' has no UN/LOCODE mapping — left as name, set manually."))
        return value
    }
}
