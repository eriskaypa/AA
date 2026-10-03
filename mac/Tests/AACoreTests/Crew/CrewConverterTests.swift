// Tests for 09 §3.5 CrewConverter (vectors §7.5 DateSummary, §7.6 Convert) and §3.4 mapping tables.
import Foundation
import Testing
@testable import AACore

@Suite struct CrewConverterTests {
    static let now = CrewTestDates.clock.now()

    func converter(_ order: CrewDateOrder = .unknown) -> CrewConverter {
        var c = CrewConverter(sourceFile: "COMPAS.xlsx", now: Self.now, today: CrewTestDates.today, zone: CrewTestDates.athens)
        if order != .unknown { c.dates.adopt(order) }
        return c
    }

    func convert(_ values: [String: String], order: CrewDateOrder = .unknown) -> CrewRecord {
        var c = converter(order)
        return c.convert(CrewCompasHeaders.row(values))
    }

    /// A complete row that raises no flags.
    static let clean: [String: String] = [
        "First name": "Juan", "Surname": "Dela Cruz", "Code": "12345", "Nationality code": "PHL", "Nationality": "FILIPINO",
        "Date of Birth": "1990-05-12", "Gender": "M", "Rank": "MAST", "Joining Date": "2026-05-01",
        "Joining Port": "Singapore (SGP)", "Sign Off Date": "2026-11-01",
    ]

    func with(_ changes: [String: String]) -> [String: String] { Self.clean.merging(changes) { $1 } }

    func flags(_ r: CrewRecord) -> [String] { r.flags.map { "\($0.severity.rawValue)|\($0.field)|\($0.message)" } }

    @Test func cleanRowHasNoFlagsAndStampsProvenance() {
        let r = convert(Self.clean)
        #expect(r.flags.isEmpty)
        #expect(r.importedAt == "2026-09-29 10:15" && r.sourceFile == "COMPAS.xlsx")
        #expect(r.userType == "Crew" && r.signedOnOff == "On")
        #expect(r.nationality == "Philippines" && r.rawNationality == "FILIPINO")
        #expect(r.signOnPort == "SGSIN" && r.signOnPortRaw == "Singapore (SGP)")
        #expect(r.dateOfBirth == "1990-05-12" && r.signOffDate == "2026-11-01")
        #expect(r.key == "12345")
    }

    @Test func ranks() {
        // TV: 09 §7.6 rank rows
        var r = convert(with(["Rank": " mast "]))
        #expect(r.rank == "Master" && r.rankCode == "MAST" && r.flags.isEmpty)
        r = convert(with(["Rank": "3oft"]))
        #expect(r.rank == "Third Officer" && flags(r) == ["1|Rank|Rank code '3OFT' → 'Third Officer' (approximate — verify)."])
        r = convert(with(["Rank": "XYZ"]))
        #expect(r.rank == "Other" && flags(r) == ["1|Rank|Unknown rank code 'XYZ' → 'Other' (set manually)."])
        r = convert(with(["Rank": ""]))
        #expect(r.rank == "Other" && r.rankCode == "" && flags(r) == ["2|Rank|No rank in COMPAS → 'Other' (mandatory, set manually)."])
    }

    @Test func nationalityAndGender() {
        // TV: 09 §7.6 nationality / gender rows
        var r = convert(with(["Nationality code": "phl", "Nationality": "Pinoy"]))
        #expect(r.nationality == "Philippines" && r.rawNationality == "Pinoy")
        r = convert(with(["Nationality code": "", "Nationality": "Filipino"]))
        #expect(r.nationality == "Philippines" && r.rawNationality == "Filipino")
        r = convert(with(["Nationality code": "XXX", "Nationality": "Martian"]))
        #expect(r.nationality == "Martian")
        r = convert(with(["Nationality code": "", "Nationality": "Sri  Lankan"]))
        #expect(r.nationality == "Sri Lanka")
        r = convert(with(["Gender": "m"]))
        #expect(r.gender == "Male" && r.flags.isEmpty)
        r = convert(with(["Gender": "X"]))
        #expect(r.gender == "" && flags(r) == ["0|Gender|Gender code 'X' not recognised."])
    }

    @Test func ports() {
        // TV: 09 §7.6 port rows
        var r = convert(with(["Joining Port": "Marmara (TUR)"]))
        #expect(r.signOnPort == "TRMER" && flags(r) == ["1|Sign-on port|Port 'Marmara (TUR)' → TRMER (UN/LOCODE best-guess — verify)."])
        r = convert(with(["Joining Port": "Rotterdam"]))
        #expect(r.signOnPort == "Rotterdam" && flags(r) == ["1|Sign-on port|Port 'Rotterdam' has no UN/LOCODE mapping — left as name, set manually."])
        r = convert(with(["Joining Port": ""]))
        #expect(r.signOnPort == "" && flags(r) == ["2|Sign-on port|Mandatory field 'Sign-on port' is empty — missing in COMPAS, fill manually."])
        r = convert(with(["SignOff Port": ""]))
        #expect(r.signOffPort == "" && r.flags.isEmpty)
        r = convert(with(["SignOff Port": "Botas (Ceyhan) Oil T"]))
        #expect(r.signOffPort == "TRCEY" && r.signOffPortRaw == "Botas (Ceyhan) Oil T" && r.flags.isEmpty)
    }

    @Test func signOffDates() {
        // TV: 09 §7.6 sign-off rows
        var r = convert(with(["Sign Off Date": ""]))
        #expect(flags(r) == ["0|Sign-off date|No sign-off date in COMPAS — contract expiry can't be tracked until it's filled in."])
        r = convert(with(["Sign Off Date": "03/04/2026"]), order: .conflicted)
        #expect(r.signOffDate == "03/04/2026")
        #expect(flags(r) == ["2|Sign-off date|Sign-off date: '03/04/2026' left unread — this file writes dates both ways, so neither reading is safe — left as-is, set it by hand."])
        var c = converter(.dayFirst)
        r = c.convert(CrewCompasHeaders.row(with(["Sign Off Date": "03/04/2026"])))
        #expect(r.signOffDate == "2026-04-03")
        #expect(flags(r) == ["1|Sign-off date|Sign-off date: read as 3 Apr 2026 (day first); would be 4 Mar 2026 if month first"])
        #expect(c.orderDependentDates == 1 && c.unreadableDates == 0)
        var u = converter(.conflicted)
        _ = u.convert(CrewCompasHeaders.row(with(["Sign Off Date": "03/04/2026"])))
        #expect(u.unreadableDates == 1)
    }

    @Test func nextOfKin() {
        // TV: 09 §7.6 NoK rows
        var r = convert(with(["Next of Kin - Name": "Maria  Clara   Santos"]))
        #expect(r.nokFirstName == "Maria Clara" && r.nokLastName == "Santos")
        r = convert(with(["Next of Kin - Name": "Maria"]))
        #expect(r.nokFirstName == "Maria" && r.nokLastName == "")
        r = convert(with(["Next of Kin - Grade": "WIFE"]))
        #expect(r.nokRelationship == "Spouse" && r.flags.isEmpty)
        r = convert(with(["Next of Kin - Grade": "Cousin"]))
        #expect(r.nokRelationship == "Other" && flags(r) == ["0|Next of kin|Relationship 'cousin' → 'Other'."])
        r = convert(with(["Next of Kin - Grade": "Not Specified"]))
        #expect(r.nokRelationship == "Other" && r.flags.isEmpty)
        r = convert(with(["Next of Kin - Grade": ""]))
        #expect(r.nokRelationship == "")
    }

    @Test func middleNames() {
        // TV: 09 §7.6 DeriveMiddle rows
        #expect(convert(with(["Original middle name": "-", "Name": "JUAN  CARLOS", "First name": "Juan"])).middleName == "CARLOS")
        #expect(convert(with(["Name": "JUANITO", "First name": "JUAN"])).middleName == "ITO")
        #expect(convert(with(["Name": "JUAN - CARLOS", "First name": "JUAN"])).middleName == "CARLOS")
        #expect(convert(with(["Name": "PEDRO", "First name": "JUAN"])).middleName == "")
        #expect(convert(with(["Original middle name": " Jose ", "Name": "JUAN CARLOS"])).middleName == "Jose")
    }

    @Test func employeeIdAndMandatory() {
        // TV: 09 §7.6 EmployeeId / mandatory rows
        var r = convert(with(["Code": "", "CMS ID Number": "", "Passport Number": "P1"]))
        #expect(r.employeeId == "P1" && r.passportNumber == "P1")
        r = convert(with(["Code": " ", "CMS ID Number": "C9"]))
        #expect(r.employeeId == "C9")
        r = convert(with(["First name": ""]))
        #expect(flags(r).last == "2|First name|Mandatory field 'First name' is empty — missing in COMPAS, fill manually.")
        r = convert(with(["First name": "", "Surname": "", "Code": "", "Joining Date": ""]))
        #expect(r.flags.suffix(4).map(\.field) == ["First name", "Last name", "Employee ID", "Sign-on date"])
    }

    @Test func licenceOnlyWithNumber() {
        // TV: 09 §7.6 last row
        var r = convert(with(["Licence Expiry Date": "2028-01-01", "Licence Issue Date": "bad"]))
        #expect(r.cocNumber == "" && r.cocExpiry == "" && r.cocIssue == "" && r.flags.isEmpty)
        r = convert(with(["Licence Number": "COC-9", "Licence Expiry Date": "2028-01-01", "Licence Issue Date": "bad"]))
        #expect(r.cocNumber == "COC-9" && r.cocExpiry == "2028-01-01" && r.cocIssue == "bad")
        #expect(flags(r) == ["2|CoC issue|CoC issue: 'bad' is not a date AA recognises — left as-is, set it by hand."])
    }

    @Test func flagOrderFollowsFieldOrder() {
        let r = convert(with(["Gender": "Q", "Rank": "3OFT", "Joining Port": "Marmara (TUR)", "Sign Off Date": "",
                              "Passport Expiry Date": "nope", "Next of Kin - Grade": "uncle", "Code": ""]))
        #expect(r.flags.map(\.field) == ["Gender", "Rank", "Sign-on port", "Sign-off date", "Passport expiry",
                                         "Next of kin", "Employee ID"])
    }

    @Test func dateSummary() {
        // TV: 09 §7.5
        var c = converter()
        c.learnDateFormat([CrewCompasHeaders.row(["Sign Off Date": "15/07/2026"])])
        #expect(c.dateSummary() == "dates read day first (dd/mm), proved by 1 value")

        c = converter()
        c.learnDateFormat(["15/07/2026", "16/07/2026", "17/07/2026"].map { CrewCompasHeaders.row(["Sign Off Date": $0]) })
        _ = c.convert(CrewCompasHeaders.row(["Sign Off Date": "nope", "Joining Date": "bad"]))
        #expect(c.dateSummary() == "dates read day first (dd/mm), proved by 3 values, 2 could not be read")

        c = converter()
        c.learnDateFormat([])
        c.applyAnswer(.monthFirst)
        #expect(c.dateSummary() == "dates read month first (mm/dd), proved by 0 values")

        c = converter()
        c.learnDateFormat(["15/07/2026", "07/15/2026"].map { CrewCompasHeaders.row(["Sign Off Date": $0]) })
        #expect(c.dateSummary() == "dates read inconsistently — this file writes dates BOTH ways, so ambiguous ones were left unread")
        c.applyAnswer(.dayFirst)
        #expect(c.dateSummary() == "dates read day first (dd/mm) as chosen at import, although this file writes dates BOTH ways")

        c = converter()
        c.learnDateFormat([CrewCompasHeaders.row(["Sign Off Date": "2026-07-15"])])
        #expect(c.dateSummary() == "dates read in unambiguous formats only; nothing in the file said whether 03/04 means 3 April or 4 March")
    }

    @Test func mappingTablesAreComplete() {
        // 09 §3.4 table sizes and case-insensitivity
        #expect(CrewMappingTables.rank.count == 21 && CrewMappingTables.iso3Nationality.count == 28)
        #expect(CrewMappingTables.demonymNationality.count == 28 && CrewMappingTables.port.count == 17)
        #expect(CrewMappingTables.relationship.count == 13)
        #expect(CrewMappingTables.rank(for: "cg3c2") == CrewMappingTables.RankMapping(dnv: "Other", approximate: true))
        #expect(CrewMappingTables.country(forISO3: "gbr") == "United Kingdom")
        #expect(CrewMappingTables.port(forNormalised: "elba islan") == CrewMappingTables.PortMapping(unlocode: "USELI", verify: true))
        #expect(CrewMappingTables.gender(for: "f") == "Female")
    }

    @Test @MainActor func recordBuildsMember() {
        var r = convert(Self.clean)
        r.flags = [CrewReviewFlag(severity: .warning, field: "Rank", message: "x")]
        let id = UUID()
        let m = r.makeMember(id: id)
        #expect(m.id == id && m.fullName == "Juan Dela Cruz" && m.key == "12345" && m.flags.count == 1)
        #expect(m.checklist.isEmpty && m.schedule.isEmpty && m.scheduleVesselId == nil)
        #expect(m.signOnPort == "SGSIN" && m.importedAt == "2026-09-29 10:15")
    }
}
