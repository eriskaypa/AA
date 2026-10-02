// Spec: 01 §4.2.12, §3.21–3.23, DATA-135; 09 §3.1, §4.2–4.3, CREW-052 (contract status), CREW-093;
//       ARCHITECTURE.md §4.5.
import Foundation
import Observation

/// How close a crew member's contract (sign-off date) is (not persisted; rendered with its C# name).
/// The same type also carries the placeholder registry `ContractStatus.isImplemented(_:)` (Foundation).
public enum ContractStatus: Int, Sendable, CaseIterable {
    case unknown, ok, dueSoon, critical, expired

    /// The C# enum name (`Unknown`, `Ok`, `DueSoon`, `Critical`, `Expired`) — CREW-052.
    public var name: String {
        switch self {
        case .unknown: return "Unknown"
        case .ok: return "Ok"
        case .dueSoon: return "DueSoon"
        case .critical: return "Critical"
        case .expired: return "Expired"
        }
    }
}

nonisolated public struct CrewReviewFlag: JSONModel, Hashable, Sendable {
    public var severity: CrewFlagSeverity
    public var field: String
    public var message: String
    public var extra: JSONObject

    public static let jsonKeys = ["Severity", "Field", "Message"]

    public init(severity: CrewFlagSeverity = .info, field: String = "", message: String = "",
                extra: JSONObject = JSONObject()) {
        self.severity = severity; self.field = field; self.message = message; self.extra = extra
    }

    public init(json o: JSONObject, context c: JSONDecodeContext) throws(JSONModelError) {
        let r = JSONFieldReader(o, context: c, type: "CrewReviewFlag")
        severity = try r.netEnum("Severity", CrewFlagSeverity.self) ?? .info
        field = try r.string("Field") ?? ""
        message = try r.string("Message") ?? ""
        extra = r.unknownMembers(knownKeys: Self.jsonKeys)
    }

    public func toJSON(options: JSONEncodeOptions = .dataFile) -> JSONObject {
        var w = JSONObjectBuilder(options)
        w.netEnum("Severity", severity); w.string("Field", field); w.string("Message", message)
        return w.build(appending: extra)
    }
}

@MainActor @Observable
public final class CrewMember: JSONModel, @MainActor Identifiable {
    public var id: UUID
    public var checklist: [ChecklistStep]
    public var schedule: [ScheduleEntry]
    public var scheduleVesselId: UUID?
    public var employeeId = ""
    public var firstName = ""
    public var middleName = ""
    public var lastName = ""
    public var nationality = ""
    public var dateOfBirth = ""
    public var placeOfBirth = ""
    public var gender = ""
    public var height = ""
    public var eyesColor = ""
    public var hairColor = ""
    public var userType = "Crew"
    public var rank = ""
    public var rankCode = ""
    public var signedOnOff = "On"
    public var company = ""
    public var vessel = ""
    public var signOnDate = ""
    public var signOnPort = ""
    public var signOnPortRaw = ""
    public var signOffDate = ""
    public var signOffPort = ""
    public var signOffPortRaw = ""
    public var passportNumber = ""
    public var passportExpiry = ""
    public var passportIssued = ""
    public var seamansBookNumber = ""
    public var seamansBookExpiry = ""
    public var seamansBookIssued = ""
    public var cocNumber = ""
    public var cocExpiry = ""
    public var cocIssue = ""
    public var healthCertExpiry = ""
    public var nokFirstName = ""
    public var nokLastName = ""
    public var nokRelationship = ""
    public var rawNationality = ""
    public var flags: [CrewReviewFlag]
    public var importedAt = ""
    public var sourceFile = ""
    @ObservationIgnored public var extra = JSONObject()

    /// The 38 persisted string keys between `ScheduleVesselId` and `Flags`, in emission order.
    static let stringKeys = ["EmployeeId", "FirstName", "MiddleName", "LastName", "Nationality", "DateOfBirth",
                             "PlaceOfBirth", "Gender", "Height", "EyesColor", "HairColor", "UserType", "Rank",
                             "RankCode", "SignedOnOff", "Company", "Vessel", "SignOnDate", "SignOnPort",
                             "SignOnPortRaw", "SignOffDate", "SignOffPort", "SignOffPortRaw", "PassportNumber",
                             "PassportExpiry", "PassportIssued", "SeamansBookNumber", "SeamansBookExpiry",
                             "SeamansBookIssued", "CocNumber", "CocExpiry", "CocIssue", "HealthCertExpiry",
                             "NokFirstName", "NokLastName", "NokRelationship", "RawNationality"]

    public static let jsonKeys = ["Id", "Checklist", "Schedule", "ScheduleVesselId"] + stringKeys
        + ["Flags", "ImportedAt", "SourceFile"]

    public init(id: UUID = UUID()) {
        self.id = id; checklist = []; schedule = []; scheduleVesselId = nil; flags = []
    }

    /// Reads/writes one of the string fields by its JSON key.
    func stringField(_ key: String) -> String {
        switch key {
        case "EmployeeId": return employeeId
        case "FirstName": return firstName
        case "MiddleName": return middleName
        case "LastName": return lastName
        case "Nationality": return nationality
        case "DateOfBirth": return dateOfBirth
        case "PlaceOfBirth": return placeOfBirth
        case "Gender": return gender
        case "Height": return height
        case "EyesColor": return eyesColor
        case "HairColor": return hairColor
        case "UserType": return userType
        case "Rank": return rank
        case "RankCode": return rankCode
        case "SignedOnOff": return signedOnOff
        case "Company": return company
        case "Vessel": return vessel
        case "SignOnDate": return signOnDate
        case "SignOnPort": return signOnPort
        case "SignOnPortRaw": return signOnPortRaw
        case "SignOffDate": return signOffDate
        case "SignOffPort": return signOffPort
        case "SignOffPortRaw": return signOffPortRaw
        case "PassportNumber": return passportNumber
        case "PassportExpiry": return passportExpiry
        case "PassportIssued": return passportIssued
        case "SeamansBookNumber": return seamansBookNumber
        case "SeamansBookExpiry": return seamansBookExpiry
        case "SeamansBookIssued": return seamansBookIssued
        case "CocNumber": return cocNumber
        case "CocExpiry": return cocExpiry
        case "CocIssue": return cocIssue
        case "HealthCertExpiry": return healthCertExpiry
        case "NokFirstName": return nokFirstName
        case "NokLastName": return nokLastName
        case "NokRelationship": return nokRelationship
        case "RawNationality": return rawNationality
        default: return ""
        }
    }

    func setStringField(_ key: String, _ v: String) {
        switch key {
        case "EmployeeId": employeeId = v
        case "FirstName": firstName = v
        case "MiddleName": middleName = v
        case "LastName": lastName = v
        case "Nationality": nationality = v
        case "DateOfBirth": dateOfBirth = v
        case "PlaceOfBirth": placeOfBirth = v
        case "Gender": gender = v
        case "Height": height = v
        case "EyesColor": eyesColor = v
        case "HairColor": hairColor = v
        case "UserType": userType = v
        case "Rank": rank = v
        case "RankCode": rankCode = v
        case "SignedOnOff": signedOnOff = v
        case "Company": company = v
        case "Vessel": vessel = v
        case "SignOnDate": signOnDate = v
        case "SignOnPort": signOnPort = v
        case "SignOnPortRaw": signOnPortRaw = v
        case "SignOffDate": signOffDate = v
        case "SignOffPort": signOffPort = v
        case "SignOffPortRaw": signOffPortRaw = v
        case "PassportNumber": passportNumber = v
        case "PassportExpiry": passportExpiry = v
        case "PassportIssued": passportIssued = v
        case "SeamansBookNumber": seamansBookNumber = v
        case "SeamansBookExpiry": seamansBookExpiry = v
        case "SeamansBookIssued": seamansBookIssued = v
        case "CocNumber": cocNumber = v
        case "CocExpiry": cocExpiry = v
        case "CocIssue": cocIssue = v
        case "HealthCertExpiry": healthCertExpiry = v
        case "NokFirstName": nokFirstName = v
        case "NokLastName": nokLastName = v
        case "NokRelationship": nokRelationship = v
        case "RawNationality": rawNationality = v
        default: break
        }
    }

    public init(json o: JSONObject, context c: JSONDecodeContext) throws(JSONModelError) {
        let r = JSONFieldReader(o, context: c, type: "CrewMember")
        id = try r.guid("Id") ?? c.newGuid()
        checklist = try r.modelArray("Checklist", ChecklistStep.self) ?? []
        schedule = try r.modelArray("Schedule", ScheduleEntry.self) ?? []
        scheduleVesselId = try r.guid("ScheduleVesselId")
        flags = []
        for k in CrewMember.stringKeys {
            if let v = try r.string(k) { setStringField(k, v) }
        }
        flags = try r.modelArray("Flags", CrewReviewFlag.self) ?? []
        importedAt = try r.string("ImportedAt") ?? ""
        sourceFile = try r.string("SourceFile") ?? ""
        extra = r.unknownMembers(knownKeys: Self.jsonKeys)
    }

    public func toJSON(options: JSONEncodeOptions = .dataFile) -> JSONObject {
        var w = JSONObjectBuilder(options)
        w.guid("Id", id); w.modelArray("Checklist", checklist); w.modelArray("Schedule", schedule)
        w.optionalGuid("ScheduleVesselId", scheduleVesselId)
        for k in CrewMember.stringKeys { w.string(k, stringField(k)) }
        w.modelArray("Flags", flags); w.string("ImportedAt", importedAt); w.string("SourceFile", sourceFile)
        return w.build(appending: extra)
    }

    // MARK: Computed (CrewMember.cs, 09 §3.1)

    /// Non-blank of First, Middle, Last joined by one space (parts are not trimmed).
    public var fullName: String {
        [firstName, middleName, lastName].filter { !NetText.isBlank($0) }.joined(separator: " ")
    }

    /// EmployeeId if not blank (untrimmed), else `"{First}|{Last}".Trim('|')`.
    public var key: String {
        if !NetText.isBlank(employeeId) { return employeeId }
        return NetText.trim("\(firstName)|\(lastName)", characters: [0x7C])
    }

    public var hasFlags: Bool { !flags.isEmpty }
    public var hasErrors: Bool { flags.contains { $0.severity == .error } }
    public var signOffDateValue: NetDateTime? { CrewMember.parseDate(signOffDate) }

    /// Whole calendar days from `today` to the sign-off date (negative = past); nil without a parseable date.
    public func daysUntilSignOff(today: CivilDate) -> Int? {
        guard let d = signOffDateValue else { return nil }
        return today.days(to: d.civilDate)
    }

    /// DATA-135 / CREW-052: Unknown (no date); Expired (< 0); Critical (≤ criticalDays); DueSoon (≤ soonDays); Ok.
    public func contractStatus(on today: CivilDate, criticalDays: Int = 30, soonDays: Int = 60) -> ContractStatus {
        guard let days = daysUntilSignOff(today: today) else { return .unknown }
        if days < 0 { return .expired }
        if days <= criticalDays { return .critical }
        if days <= soonDays { return .dueSoon }
        return .ok
    }

    /// The app-wide tolerant date parser (09 §3.1, §6.3): the three exact formats `yyyy-MM-dd`, `yyyy/MM/dd`,
    /// `yyyy.MM.dd`, then the .NET `DateTime.TryParse` emulation. The algorithm is F2's `NetDateParser`
    /// (ARCHITECTURE.md §6.5, `Services/NetDateParser.swift`); this forwards to it (current time zone, no `today`).
    public nonisolated static func parseDate(_ s: String?) -> NetDateTime? {
        NetDateParser.parse(s)
    }
}
