// Spec: 01 §4.2.20 (Ui keys, emission order, defaults), DATA-217 (key owners), 13 §3.11.1 (PerDeviceUiKeys),
//       DECISIONS 03 Q-3 (reload keeps per-device keys); ARCHITECTURE.md §4.9.
import Foundation
import Observation

@MainActor @Observable
public final class UiState: JSONModel {
    public var windowLeft: Double?
    public var windowTop: Double?
    public var windowWidth: Double?
    public var windowHeight: Double?
    public var windowState: String?
    public var selectedMainTabIndex: Int
    public var selectedEquipmentId: UUID?
    public var selectedTaskId: UUID?
    public var selectedProcedureId: UUID?
    public var selectedVesselId: UUID?
    public var calendarSelectedDate: NetDateTime?
    public var calendarViewMode: String?
    public var calendarFontScale: Double?
    public var showShortcutBar: Bool
    public var quickViewPinIds: [UUID]
    /// Tab id → colour string; may hold tab names this build does not know (preserved, edited key by key).
    public var tabColors: OrderedMap<String>
    /// Tab ids in display order; unknown entries are preserved.
    public var tabOrder: [String]
    public var dueWindowWidth: Double?
    public var dueWindowHeight: Double?
    public var mapFocusedItemId: UUID?
    public var sortAZ: OrderedMap<Bool>
    /// Key `"{ItemKind name}|{group name}"`; missing = expanded.
    public var groupExpanded: OrderedMap<Bool>
    public var crewSortMode: String?
    public var crewTableColumns: [String]
    public var crewTableShownColumns: [String]
    public var crewTableDateFormat: String?
    public var crewTableDateSeparator: String?
    public var lastDigestDate: String?
    @ObservationIgnored public var extra = JSONObject()

    public static let jsonKeys = ["WindowLeft", "WindowTop", "WindowWidth", "WindowHeight", "WindowState",
                                  "SelectedMainTabIndex", "SelectedEquipmentId", "SelectedTaskId",
                                  "SelectedProcedureId", "SelectedVesselId", "CalendarSelectedDate",
                                  "CalendarViewMode", "CalendarFontScale", "ShowShortcutBar", "QuickViewPinIds",
                                  "TabColors", "TabOrder", "DueWindowWidth", "DueWindowHeight", "MapFocusedItemId",
                                  "SortAZ", "GroupExpanded", "CrewSortMode", "CrewTableColumns",
                                  "CrewTableShownColumns", "CrewTableDateFormat", "CrewTableDateSeparator",
                                  "LastDigestDate"]

    /// The 16 per-device keys of 13 §3.11.1, identical order (the Flash Sync denylist).
    public static let perDeviceKeyNames = ["WindowLeft", "WindowTop", "WindowWidth", "WindowHeight", "WindowState",
                                           "DueWindowWidth", "DueWindowHeight", "SelectedMainTabIndex",
                                           "SelectedEquipmentId", "SelectedTaskId", "SelectedProcedureId",
                                           "SelectedVesselId", "CalendarSelectedDate", "MapFocusedItemId",
                                           "GroupExpanded", "LastDigestDate"]

    public init() {
        selectedMainTabIndex = 0; showShortcutBar = true; quickViewPinIds = []; tabColors = OrderedMap()
        tabOrder = []; sortAZ = OrderedMap(); groupExpanded = OrderedMap(); crewTableColumns = []
        crewTableShownColumns = []
    }

    public init(json o: JSONObject, context c: JSONDecodeContext) throws(JSONModelError) {
        let r = JSONFieldReader(o, context: c, type: "UiState")
        windowLeft = try r.double("WindowLeft")
        windowTop = try r.double("WindowTop")
        windowWidth = try r.double("WindowWidth")
        windowHeight = try r.double("WindowHeight")
        windowState = try r.string("WindowState")
        selectedMainTabIndex = try r.int("SelectedMainTabIndex") ?? 0
        selectedEquipmentId = try r.guid("SelectedEquipmentId")
        selectedTaskId = try r.guid("SelectedTaskId")
        selectedProcedureId = try r.guid("SelectedProcedureId")
        selectedVesselId = try r.guid("SelectedVesselId")
        calendarSelectedDate = try r.date("CalendarSelectedDate")
        calendarViewMode = try r.string("CalendarViewMode")
        calendarFontScale = try r.double("CalendarFontScale")
        showShortcutBar = try r.bool("ShowShortcutBar") ?? true
        quickViewPinIds = try r.guidArray("QuickViewPinIds") ?? []
        tabColors = try r.stringMap("TabColors") ?? OrderedMap()
        tabOrder = try r.stringArray("TabOrder") ?? []
        dueWindowWidth = try r.double("DueWindowWidth")
        dueWindowHeight = try r.double("DueWindowHeight")
        mapFocusedItemId = try r.guid("MapFocusedItemId")
        sortAZ = try r.boolMap("SortAZ") ?? OrderedMap()
        groupExpanded = try r.boolMap("GroupExpanded") ?? OrderedMap()
        crewSortMode = try r.string("CrewSortMode")
        crewTableColumns = try r.stringArray("CrewTableColumns") ?? []
        crewTableShownColumns = try r.stringArray("CrewTableShownColumns") ?? []
        crewTableDateFormat = try r.string("CrewTableDateFormat")
        crewTableDateSeparator = try r.string("CrewTableDateSeparator")
        lastDigestDate = try r.string("LastDigestDate")
        extra = r.unknownMembers(knownKeys: Self.jsonKeys)
    }

    public func toJSON(options: JSONEncodeOptions = .dataFile) -> JSONObject {
        var w = JSONObjectBuilder(options)
        w.optionalDouble("WindowLeft", windowLeft); w.optionalDouble("WindowTop", windowTop)
        w.optionalDouble("WindowWidth", windowWidth); w.optionalDouble("WindowHeight", windowHeight)
        w.optionalString("WindowState", windowState); w.int("SelectedMainTabIndex", selectedMainTabIndex)
        w.optionalGuid("SelectedEquipmentId", selectedEquipmentId); w.optionalGuid("SelectedTaskId", selectedTaskId)
        w.optionalGuid("SelectedProcedureId", selectedProcedureId); w.optionalGuid("SelectedVesselId", selectedVesselId)
        w.optionalDate("CalendarSelectedDate", calendarSelectedDate)
        w.optionalString("CalendarViewMode", calendarViewMode)
        w.optionalDouble("CalendarFontScale", calendarFontScale); w.bool("ShowShortcutBar", showShortcutBar)
        w.guidArray("QuickViewPinIds", quickViewPinIds); w.stringMap("TabColors", tabColors)
        w.stringArray("TabOrder", tabOrder); w.optionalDouble("DueWindowWidth", dueWindowWidth)
        w.optionalDouble("DueWindowHeight", dueWindowHeight); w.optionalGuid("MapFocusedItemId", mapFocusedItemId)
        w.boolMap("SortAZ", sortAZ); w.boolMap("GroupExpanded", groupExpanded)
        w.optionalString("CrewSortMode", crewSortMode); w.stringArray("CrewTableColumns", crewTableColumns)
        w.stringArray("CrewTableShownColumns", crewTableShownColumns)
        w.optionalString("CrewTableDateFormat", crewTableDateFormat)
        w.optionalString("CrewTableDateSeparator", crewTableDateSeparator)
        w.optionalString("LastDigestDate", lastDigestDate)
        return w.build(appending: extra)
    }

    /// DECISIONS 03 Q-3: after a reload the per-device keys (window geometry, selections, …) come from `other`
    /// (the state this Mac had before the reload); every shared key keeps the loaded value.
    public func copyPerDeviceValues(from other: UiState) {
        windowLeft = other.windowLeft; windowTop = other.windowTop
        windowWidth = other.windowWidth; windowHeight = other.windowHeight; windowState = other.windowState
        dueWindowWidth = other.dueWindowWidth; dueWindowHeight = other.dueWindowHeight
        selectedMainTabIndex = other.selectedMainTabIndex
        selectedEquipmentId = other.selectedEquipmentId; selectedTaskId = other.selectedTaskId
        selectedProcedureId = other.selectedProcedureId; selectedVesselId = other.selectedVesselId
        calendarSelectedDate = other.calendarSelectedDate; mapFocusedItemId = other.mapFocusedItemId
        groupExpanded = other.groupExpanded; lastDigestDate = other.lastDigestDate
    }
}
