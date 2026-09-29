// Spec: 01 §4.2.1 (root keys, order, fresh-database golden), DATA-022–024, DATA-031; ARCHITECTURE.md §4.10.
import Foundation
import Observation

@MainActor @Observable
public final class AppData: JSONModel {
    public var equipment: [Equipment]
    public var tasks: [TaskItem]
    public var procedures: [Procedure]
    public var vessels: [Vessel]
    public var groups: [ItemGroup]
    public var crew: [CrewMember]
    public var log: [LogEntry]
    public var checklistTemplates: [ChecklistTemplate]
    public var listGroups: [ListGroup]
    public var quickBuckets: [QuickBucket]
    public var ports: [PortRecord]
    public var scheduleTemplates: [ScheduleTemplate]
    public var trash: [TrashedItem]
    public var sire: SireState
    public var ui: UiState
    /// `.local`; stamped on user saves (DATA-031).
    public var lastModified: NetDateTime?
    public var schemaVersion: Int
    /// Top-level unknown keys, emitted last.
    @ObservationIgnored public var extra = JSONObject()

    public static let jsonKeys = ["Equipment", "Tasks", "Procedures", "Vessels", "Groups", "Crew", "Log",
                                  "ChecklistTemplates", "ListGroups", "QuickBuckets", "Ports", "ScheduleTemplates",
                                  "Trash", "Sire", "Ui", "LastModified", "SchemaVersion"]

    public init() {
        equipment = []; tasks = []; procedures = []; vessels = []; groups = []; crew = []; log = []
        checklistTemplates = []; listGroups = []; quickBuckets = []; ports = []; scheduleTemplates = []; trash = []
        sire = SireState(); ui = UiState(); lastModified = nil; schemaVersion = 0
    }

    public init(json o: JSONObject, context c: JSONDecodeContext) throws(JSONModelError) {
        let r = JSONFieldReader(o, context: c, type: "AppData")
        equipment = try r.modelArray("Equipment", Equipment.self) ?? []
        tasks = try r.modelArray("Tasks", TaskItem.self) ?? []
        procedures = try r.modelArray("Procedures", Procedure.self) ?? []
        vessels = try r.modelArray("Vessels", Vessel.self) ?? []
        groups = try r.modelArray("Groups", ItemGroup.self) ?? []
        crew = try r.modelArray("Crew", CrewMember.self) ?? []
        log = try r.modelArray("Log", LogEntry.self) ?? []
        checklistTemplates = try r.modelArray("ChecklistTemplates", ChecklistTemplate.self) ?? []
        listGroups = try r.modelArray("ListGroups", ListGroup.self) ?? []
        quickBuckets = try r.modelArray("QuickBuckets", QuickBucket.self) ?? []
        ports = try r.modelArray("Ports", PortRecord.self) ?? []
        scheduleTemplates = try r.modelArray("ScheduleTemplates", ScheduleTemplate.self) ?? []
        trash = try r.modelArray("Trash", TrashedItem.self) ?? []
        sire = try r.model("Sire", SireState.self) ?? SireState()
        ui = try r.model("Ui", UiState.self) ?? UiState()
        lastModified = try r.date("LastModified")
        schemaVersion = try r.int("SchemaVersion") ?? 0
        extra = r.unknownMembers(knownKeys: Self.jsonKeys)
    }

    public func toJSON(options: JSONEncodeOptions = .dataFile) -> JSONObject {
        var w = JSONObjectBuilder(options)
        w.modelArray("Equipment", equipment); w.modelArray("Tasks", tasks); w.modelArray("Procedures", procedures)
        w.modelArray("Vessels", vessels); w.modelArray("Groups", groups); w.modelArray("Crew", crew)
        w.modelArray("Log", log); w.modelArray("ChecklistTemplates", checklistTemplates)
        w.modelArray("ListGroups", listGroups); w.modelArray("QuickBuckets", quickBuckets)
        w.modelArray("Ports", ports); w.modelArray("ScheduleTemplates", scheduleTemplates)
        w.modelArray("Trash", trash); w.model("Sire", sire); w.model("Ui", ui)
        w.optionalDate("LastModified", lastModified); w.int("SchemaVersion", schemaVersion)
        return w.build(appending: extra)
    }
}
