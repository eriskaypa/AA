// Spec: 01 §4.2.9–4.2.10, §3.21 (keys), §3.22 (display strings), §3.25 / DATA-139 (copy helpers),
//       §3.23 (ShipJob.DaysUntilDue); ARCHITECTURE.md §4.3–4.4.
import Foundation
import Observation

@MainActor @Observable
public final class Vessel: HierarchyItem {
    public var quickCards: [QuickCard]
    public var jobs: [ShipJob]
    public var notificationsEnabled: Bool
    public var portCalls: [PortCall]

    public override class var jsonKeys: [String] {
        ["QuickCards", "Jobs", "NotificationsEnabled", "PortCalls"] + baseJSONKeys
    }
    public override var kind: ItemKind { .vessel }

    public override init(id: UUID = UUID(), name: String = "") {
        quickCards = []; jobs = []; notificationsEnabled = true; portCalls = []
        super.init(id: id, name: name)
    }

    public required init(json: JSONObject, context: JSONDecodeContext) throws(JSONModelError) {
        let r = JSONFieldReader(json, context: context, type: "Vessel")
        quickCards = try r.modelArray("QuickCards", QuickCard.self) ?? []
        jobs = try r.modelArray("Jobs", ShipJob.self) ?? []
        notificationsEnabled = try r.bool("NotificationsEnabled") ?? true
        portCalls = try r.modelArray("PortCalls", PortCall.self) ?? []
        try super.init(json: json, context: context)
        extra = unknownMembers(json, context, keys: Vessel.jsonKeys)
    }

    public override func toJSON(options: JSONEncodeOptions = .dataFile) -> JSONObject {
        var w = JSONObjectBuilder(options)
        w.modelArray("QuickCards", quickCards); w.modelArray("Jobs", jobs)
        w.bool("NotificationsEnabled", notificationsEnabled); w.modelArray("PortCalls", portCalls)
        encodeBase(into: &w)
        return w.build(appending: extra)
    }
}

@MainActor @Observable
public final class QuickCard: JSONModel, @MainActor Identifiable {
    public var id: UUID
    public var title: String
    /// Imported-copy relative path (`files/…`), an absolute in-place path, or a URL.
    public var target: String
    public var isLink: Bool
    public var linkInPlace: Bool
    public var isFolder: Bool
    public var icon: String
    /// WPF colour string (#AARRGGBB / #RRGGBB).
    public var color: String
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    @ObservationIgnored public var extra = JSONObject()

    public static let jsonKeys = ["Id", "Title", "Target", "IsLink", "LinkInPlace", "IsFolder", "Icon", "Color",
                                  "X", "Y", "Width", "Height"]

    public init(id: UUID = UUID(), title: String = "") {
        self.id = id; self.title = title; target = ""; isLink = false; linkInPlace = false; isFolder = false
        icon = "\u{2693}"; color = "#FF1E88E5"; x = 24; y = 24; width = 180; height = 120
    }

    public init(json o: JSONObject, context c: JSONDecodeContext) throws(JSONModelError) {
        let r = JSONFieldReader(o, context: c, type: "QuickCard")
        id = try r.guid("Id") ?? c.newGuid()
        title = try r.string("Title") ?? ""
        target = try r.string("Target") ?? ""
        isLink = try r.bool("IsLink") ?? false
        linkInPlace = try r.bool("LinkInPlace") ?? false
        isFolder = try r.bool("IsFolder") ?? false
        icon = try r.string("Icon") ?? "\u{2693}"
        color = try r.string("Color") ?? "#FF1E88E5"
        x = try r.double("X") ?? 24
        y = try r.double("Y") ?? 24
        width = try r.double("Width") ?? 180
        height = try r.double("Height") ?? 120
        extra = r.unknownMembers(knownKeys: Self.jsonKeys)
    }

    public func toJSON(options: JSONEncodeOptions = .dataFile) -> JSONObject {
        var w = JSONObjectBuilder(options)
        w.guid("Id", id); w.string("Title", title); w.string("Target", target); w.bool("IsLink", isLink)
        w.bool("LinkInPlace", linkInPlace); w.bool("IsFolder", isFolder); w.string("Icon", icon)
        w.string("Color", color); w.double("X", x); w.double("Y", y); w.double("Width", width)
        w.double("Height", height)
        return w.build(appending: extra)
    }

    /// DATA-139: a new object with the SAME Id and every field copied (`extra` too).
    public func clone() -> QuickCard {
        let c = QuickCard(id: id)
        c.copy(from: self)
        c.extra = extra
        return c
    }

    /// DATA-139: copies every field except `Id`.
    public func copy(from o: QuickCard) {
        title = o.title; target = o.target; isLink = o.isLink; linkInPlace = o.linkInPlace; isFolder = o.isFolder
        icon = o.icon; color = o.color; x = o.x; y = o.y; width = o.width; height = o.height
    }
}

/// A Shippalm work order (no Id; keyed by `JobNo`, case-insensitive).
@MainActor @Observable
public final class ShipJob: JSONModel, @MainActor Identifiable {
    public var jobNo: String
    public var title: String
    public var workPlanNo: String
    public var status: String
    public var classCode: String
    public var category: String
    public var responsibleRank: String
    public var functionNo: String
    public var functionDescription: String
    public var interval: String
    public var dueStatus: String
    public var dueDate: String
    public var finishedDate: String
    public var lastDoneDate: String
    public var overdueDays: Int
    public var notify: Bool
    public var isCompleted: Bool
    public var completedDate: String
    public var importedAt: String
    @ObservationIgnored public var extra = JSONObject()

    public static let jsonKeys = ["JobNo", "Title", "WorkPlanNo", "Status", "ClassCode", "Category",
                                  "ResponsibleRank", "FunctionNo", "FunctionDescription", "Interval", "DueStatus",
                                  "DueDate", "FinishedDate", "LastDoneDate", "OverdueDays", "Notify", "IsCompleted",
                                  "CompletedDate", "ImportedAt"]

    /// Not persisted: the invariant lower-cased JobNo.
    public var id: String { NetText.toLowerInvariant(jobNo) }

    public init(jobNo: String = "") {
        self.jobNo = jobNo; title = ""; workPlanNo = ""; status = ""; classCode = ""; category = ""
        responsibleRank = ""; functionNo = ""; functionDescription = ""; interval = ""; dueStatus = ""
        dueDate = ""; finishedDate = ""; lastDoneDate = ""; overdueDays = 0; notify = false; isCompleted = false
        completedDate = ""; importedAt = ""
    }

    public init(json o: JSONObject, context c: JSONDecodeContext) throws(JSONModelError) {
        let r = JSONFieldReader(o, context: c, type: "ShipJob")
        jobNo = try r.string("JobNo") ?? ""
        title = try r.string("Title") ?? ""
        workPlanNo = try r.string("WorkPlanNo") ?? ""
        status = try r.string("Status") ?? ""
        classCode = try r.string("ClassCode") ?? ""
        category = try r.string("Category") ?? ""
        responsibleRank = try r.string("ResponsibleRank") ?? ""
        functionNo = try r.string("FunctionNo") ?? ""
        functionDescription = try r.string("FunctionDescription") ?? ""
        interval = try r.string("Interval") ?? ""
        dueStatus = try r.string("DueStatus") ?? ""
        dueDate = try r.string("DueDate") ?? ""
        finishedDate = try r.string("FinishedDate") ?? ""
        lastDoneDate = try r.string("LastDoneDate") ?? ""
        overdueDays = try r.int("OverdueDays") ?? 0
        notify = try r.bool("Notify") ?? false
        isCompleted = try r.bool("IsCompleted") ?? false
        completedDate = try r.string("CompletedDate") ?? ""
        importedAt = try r.string("ImportedAt") ?? ""
        extra = r.unknownMembers(knownKeys: Self.jsonKeys)
    }

    public func toJSON(options: JSONEncodeOptions = .dataFile) -> JSONObject {
        var w = JSONObjectBuilder(options)
        w.string("JobNo", jobNo); w.string("Title", title); w.string("WorkPlanNo", workPlanNo)
        w.string("Status", status); w.string("ClassCode", classCode); w.string("Category", category)
        w.string("ResponsibleRank", responsibleRank); w.string("FunctionNo", functionNo)
        w.string("FunctionDescription", functionDescription); w.string("Interval", interval)
        w.string("DueStatus", dueStatus); w.string("DueDate", dueDate); w.string("FinishedDate", finishedDate)
        w.string("LastDoneDate", lastDoneDate); w.int("OverdueDays", overdueDays); w.bool("Notify", notify)
        w.bool("IsCompleted", isCompleted); w.string("CompletedDate", completedDate)
        w.string("ImportedAt", importedAt)
        return w.build(appending: extra)
    }

    /// `CrewMember.parseDate(dueDate)`.
    public var dueDateValue: NetDateTime? { CrewMember.parseDate(dueDate) }

    /// Whole days from `today` until the due date (negative = overdue); nil without a valid due date.
    public func daysUntilDue(today: CivilDate) -> Int? {
        guard let d = dueDateValue else { return nil }
        return today.days(to: d.civilDate)
    }

    /// DATA-139: copies all 19 persisted fields (incl. JobNo).
    public func copy(from o: ShipJob) {
        jobNo = o.jobNo; title = o.title; workPlanNo = o.workPlanNo; status = o.status; classCode = o.classCode
        category = o.category; responsibleRank = o.responsibleRank; functionNo = o.functionNo
        functionDescription = o.functionDescription; interval = o.interval; dueStatus = o.dueStatus
        dueDate = o.dueDate; finishedDate = o.finishedDate; lastDoneDate = o.lastDoneDate
        overdueDays = o.overdueDays; notify = o.notify; isCompleted = o.isCompleted
        completedDate = o.completedDate; importedAt = o.importedAt
    }
}

@MainActor @Observable
public final class PortCall: JSONModel, @MainActor Identifiable {
    public var id: UUID
    public var portName: String
    public var country: String
    public var unLocode: String
    public var portFacility: String
    public var pfNo: String
    public var arrivalDate: String
    public var arrivalTime: String
    public var departureDate: String
    public var departureTime: String
    public var securityLevelPort: String
    public var securityLevelVessel: String
    public var sspFollowed: String
    public var specialMeasures: String
    public var importedAt: String
    @ObservationIgnored public var extra = JSONObject()

    public static let jsonKeys = ["Id", "PortName", "Country", "UnLocode", "PortFacility", "PfNo", "ArrivalDate",
                                  "ArrivalTime", "DepartureDate", "DepartureTime", "SecurityLevelPort",
                                  "SecurityLevelVessel", "SspFollowed", "SpecialMeasures", "ImportedAt"]

    public init(id: UUID = UUID(), portName: String = "") {
        self.id = id; self.portName = portName; country = ""; unLocode = ""; portFacility = ""; pfNo = ""
        arrivalDate = ""; arrivalTime = ""; departureDate = ""; departureTime = ""; securityLevelPort = ""
        securityLevelVessel = ""; sspFollowed = ""; specialMeasures = ""; importedAt = ""
    }

    public init(json o: JSONObject, context c: JSONDecodeContext) throws(JSONModelError) {
        let r = JSONFieldReader(o, context: c, type: "PortCall")
        id = try r.guid("Id") ?? c.newGuid()
        portName = try r.string("PortName") ?? ""
        country = try r.string("Country") ?? ""
        unLocode = try r.string("UnLocode") ?? ""
        portFacility = try r.string("PortFacility") ?? ""
        pfNo = try r.string("PfNo") ?? ""
        arrivalDate = try r.string("ArrivalDate") ?? ""
        arrivalTime = try r.string("ArrivalTime") ?? ""
        departureDate = try r.string("DepartureDate") ?? ""
        departureTime = try r.string("DepartureTime") ?? ""
        securityLevelPort = try r.string("SecurityLevelPort") ?? ""
        securityLevelVessel = try r.string("SecurityLevelVessel") ?? ""
        sspFollowed = try r.string("SspFollowed") ?? ""
        specialMeasures = try r.string("SpecialMeasures") ?? ""
        importedAt = try r.string("ImportedAt") ?? ""
        extra = r.unknownMembers(knownKeys: Self.jsonKeys)
    }

    public func toJSON(options: JSONEncodeOptions = .dataFile) -> JSONObject {
        var w = JSONObjectBuilder(options)
        w.guid("Id", id); w.string("PortName", portName); w.string("Country", country)
        w.string("UnLocode", unLocode); w.string("PortFacility", portFacility); w.string("PfNo", pfNo)
        w.string("ArrivalDate", arrivalDate); w.string("ArrivalTime", arrivalTime)
        w.string("DepartureDate", departureDate); w.string("DepartureTime", departureTime)
        w.string("SecurityLevelPort", securityLevelPort); w.string("SecurityLevelVessel", securityLevelVessel)
        w.string("SspFollowed", sspFollowed); w.string("SpecialMeasures", specialMeasures)
        w.string("ImportedAt", importedAt)
        return w.build(appending: extra)
    }

    /// `"{portName.ToLowerInvariant()}@{ArrivalDate}"`.
    public var key: String { NetText.toLowerInvariant(portName) + "@" + arrivalDate }
    public var arrivalValue: NetDateTime? { CrewMember.parseDate(arrivalDate) }
    public var displayName: String { country.isEmpty ? portName : "\(portName), \(country)" }
    public var arrivalDisplay: String { NetText.trim("\(arrivalDate) \(arrivalTime)") }
    public var departureDisplay: String { NetText.trim("\(departureDate) \(departureTime)") }
}

/// C# `Port` (renamed: `Foundation.Port` exists — JSON unchanged).
@MainActor @Observable
public final class PortRecord: JSONModel, @MainActor Identifiable {
    public var id: UUID
    public var name: String
    public var country: String
    public var unLocode: String
    public var visits: [PortVisit]
    @ObservationIgnored public var extra = JSONObject()

    public static let jsonKeys = ["Id", "Name", "Country", "UnLocode", "Visits"]

    public init(id: UUID = UUID(), name: String = "", country: String = "", unLocode: String = "", visits: [PortVisit] = []) {
        self.id = id; self.name = name; self.country = country; self.unLocode = unLocode; self.visits = visits
    }

    public init(json o: JSONObject, context c: JSONDecodeContext) throws(JSONModelError) {
        let r = JSONFieldReader(o, context: c, type: "Port")
        id = try r.guid("Id") ?? c.newGuid()
        name = try r.string("Name") ?? ""
        country = try r.string("Country") ?? ""
        unLocode = try r.string("UnLocode") ?? ""
        visits = try r.modelArray("Visits", PortVisit.self) ?? []
        extra = r.unknownMembers(knownKeys: Self.jsonKeys)
    }

    public func toJSON(options: JSONEncodeOptions = .dataFile) -> JSONObject {
        var w = JSONObjectBuilder(options)
        w.guid("Id", id); w.string("Name", name); w.string("Country", country); w.string("UnLocode", unLocode)
        w.modelArray("Visits", visits)
        return w.build(appending: extra)
    }

    /// `UnLocode != "" ? UnLocode.ToLowerInvariant() : (Name + "|" + Country).ToLowerInvariant()`.
    public var key: String {
        unLocode.isEmpty ? NetText.toLowerInvariant(name + "|" + country) : NetText.toLowerInvariant(unLocode)
    }
    /// `(UnLocode != "" ? "{Name} ({UnLocode})" : Name) + (Country != "" ? ", {Country}" : "")`.
    public var display: String {
        (unLocode.isEmpty ? name : "\(name) (\(unLocode))") + (country.isEmpty ? "" : ", \(country)")
    }
}

/// One vessel's visit to a port (value record, no Id).
nonisolated public struct PortVisit: JSONModel, Hashable, Sendable {
    public var vesselName: String
    public var vesselId: UUID?
    public var arrivalDate: String
    public var arrivalTime: String
    public var departureDate: String
    public var departureTime: String
    public var importedAt: String
    public var extra: JSONObject

    public static let jsonKeys = ["VesselName", "VesselId", "ArrivalDate", "ArrivalTime", "DepartureDate",
                                  "DepartureTime", "ImportedAt"]

    public init(vesselName: String = "", vesselId: UUID? = nil, arrivalDate: String = "", arrivalTime: String = "",
                departureDate: String = "", departureTime: String = "", importedAt: String = "",
                extra: JSONObject = JSONObject()) {
        self.vesselName = vesselName; self.vesselId = vesselId; self.arrivalDate = arrivalDate
        self.arrivalTime = arrivalTime; self.departureDate = departureDate; self.departureTime = departureTime
        self.importedAt = importedAt; self.extra = extra
    }

    public init(json o: JSONObject, context c: JSONDecodeContext) throws(JSONModelError) {
        let r = JSONFieldReader(o, context: c, type: "PortVisit")
        vesselName = try r.string("VesselName") ?? ""
        vesselId = try r.guid("VesselId")
        arrivalDate = try r.string("ArrivalDate") ?? ""
        arrivalTime = try r.string("ArrivalTime") ?? ""
        departureDate = try r.string("DepartureDate") ?? ""
        departureTime = try r.string("DepartureTime") ?? ""
        importedAt = try r.string("ImportedAt") ?? ""
        extra = r.unknownMembers(knownKeys: Self.jsonKeys)
    }

    public func toJSON(options: JSONEncodeOptions = .dataFile) -> JSONObject {
        var w = JSONObjectBuilder(options)
        w.string("VesselName", vesselName); w.optionalGuid("VesselId", vesselId)
        w.string("ArrivalDate", arrivalDate); w.string("ArrivalTime", arrivalTime)
        w.string("DepartureDate", departureDate); w.string("DepartureTime", departureTime)
        w.string("ImportedAt", importedAt)
        return w.build(appending: extra)
    }

    /// `(VesselName + "|" + ArrivalDate + "|" + ArrivalTime).ToLowerInvariant()`.
    public var visitKey: String { NetText.toLowerInvariant("\(vesselName)|\(arrivalDate)|\(arrivalTime)") }
    public var arrivalValue: NetDateTime? { CrewMember.parseDate(arrivalDate) }
    public var arrivalDisplay: String { NetText.trim("\(arrivalDate) \(arrivalTime)") }
    public var departureDisplay: String { NetText.trim("\(departureDate) \(departureTime)") }
}
