// Spec: 03 SHELL-025 (13 tabs, persisted names incl. `CrewTab`), SHELL-028 / §3.4 (ApplyTabOrder, drop rule,
//       PersistTabOrder), §4.1 (unknown TabOrder names preserved), §6.2 (Mac labels and SF Symbols), SHELL-027/§6.3 (W-1),
//       01 DATA-035a; ARCHITECTURE.md §6.9 (writeTabOrder round-trip rule, R-57). Vectors: 03 §7.1.
import Foundation

/// The 13 main sections ("tabs"); the raw values are DATA (`UiState.TabOrder`, `UiState.TabColors`).
public enum SectionID: String, CaseIterable, Sendable, Codable {
    case equipment = "TabEquipment", tasks = "TabTasks", procedures = "TabProcedures", vessels = "TabVessels",
         calendar = "TabCalendar", board = "TabBoard", planner = "TabPlanner", map = "TabMap", crew = "CrewTab",
         lists = "TabLists", buckets = "TabBuckets", ports = "TabPorts", sire = "TabSire"

    /// Windows default order (= `allCases`).
    public static let defaultOrder: [SectionID] = SectionID.allCases

    /// The tab header (Crew without its badge).
    public var title: String {
        switch self {
        case .equipment: return "Equipment/Area"
        case .tasks: return "Tasks"
        case .procedures: return "Procedures"
        case .vessels: return "Vessels"
        case .calendar: return "Calendar"
        case .board: return "Board"
        case .planner: return "Planner"
        case .map: return "Relationship Map"
        case .crew: return "Crew"
        case .lists: return "Saved Lists"
        case .buckets: return "Buckets"
        case .ports: return "Ports"
        case .sire: return "SIRE 2.0"
        }
    }

    /// 03 §6.2 SF Symbols.
    public var symbol: String {
        switch self {
        case .equipment: return "wrench.and.screwdriver"
        case .tasks: return "checklist"
        case .procedures: return "list.number"
        case .vessels: return "ferry"
        case .calendar: return "calendar"
        case .board: return "rectangle.split.3x1"
        case .planner: return "calendar.day.timeline.left"
        case .map: return "point.3.connected.trianglepath.dotted"
        case .crew: return "person.3"
        case .lists: return "list.bullet.rectangle"
        case .buckets: return "tray.2"
        case .ports: return "mappin.and.ellipse"
        case .sire: return "checkmark.shield"
        }
    }

    /// The hierarchy kind for the four hierarchy sections.
    public var itemKind: ItemKind? {
        switch self {
        case .equipment: return .equipment
        case .tasks: return .task
        case .procedures: return .procedure
        case .vessels: return .vessel
        default: return nil
        }
    }

    public var isHierarchy: Bool { itemKind != nil }

    /// The section that shows items of `kind` (navigation by identity, never by index — W-6 fix).
    public static func section(for kind: ItemKind) -> SectionID {
        switch kind {
        case .task: return .tasks
        case .procedure: return .procedures
        case .vessel: return .vessels
        default: return .equipment
        }
    }

    /// `ApplyTabOrder` (03 §3.4): listed valid ids first (unknown and duplicate names ignored), then every unlisted
    /// section in default order.
    public static func applyTabOrder(_ stored: [String]) -> [SectionID] {
        var out: [SectionID] = []
        for name in stored {
            if let s = SectionID(rawValue: name), !out.contains(s) { out.append(s) }
        }
        for s in defaultOrder where !out.contains(s) { out.append(s) }
        return out
    }

    /// New stored TabOrder after a reorder: the 13 known ids in `order`, with every UNRECOGNISED entry of `stored`
    /// re-inserted directly after its original predecessor (at the front if it had none) — 03 §4.1 round-trip rule.
    public static func writeTabOrder(_ order: [SectionID], preserving stored: [String]) -> [String] {
        // Each result entry remembers which stored index it represents (nil = not taken from `stored`).
        var result: [(value: String, storedIndex: Int?)] = []
        var firstIndex: [String: Int] = [:]
        for (i, name) in stored.enumerated() where firstIndex[name] == nil { firstIndex[name] = i }
        var seen = Set<SectionID>()
        for s in order where !seen.contains(s) {
            seen.insert(s)
            result.append((s.rawValue, firstIndex[s.rawValue]))
        }
        for s in defaultOrder where !seen.contains(s) { result.append((s.rawValue, firstIndex[s.rawValue])) }
        var frontInsert = 0
        for (i, name) in stored.enumerated() where SectionID(rawValue: name) == nil {
            if i == 0 {
                result.insert((name, i), at: frontInsert)
                frontInsert += 1
                continue
            }
            let pred = stored[i - 1]
            var at: Int?
            if let p = result.firstIndex(where: { $0.storedIndex == i - 1 }) {
                at = p
            } else if SectionID(rawValue: pred) != nil, let p = result.firstIndex(where: { $0.value == pred }) {
                at = p                                       // predecessor was a duplicate known id
            }
            if let at {
                result.insert((name, i), at: at + 1)
                if at < frontInsert { frontInsert += 1 }
            } else {
                result.insert((name, i), at: frontInsert)
                frontInsert += 1
            }
        }
        return result.map(\.value)
    }

    /// WPF tab drop (03 §3.4): the dragged tab takes the target's index (computed before removal); same tab → nil.
    public static func dropOrder(_ order: [SectionID], dragged: SectionID, onto target: SectionID) -> [SectionID]? {
        guard dragged != target, let to = order.firstIndex(of: target), let from = order.firstIndex(of: dragged) else {
            return nil
        }
        var o = order
        o.remove(at: from)
        o.insert(dragged, at: min(to, o.count))
        return o
    }

    /// SHELL-027 / W-1 fix: apply the order first, then select `order[index]` when the index is in range.
    public static func restoredSelection(order: [SectionID], selectedIndex: Int) -> SectionID {
        (selectedIndex >= 0 && selectedIndex < order.count) ? order[selectedIndex] : (order.first ?? .equipment)
    }

    /// Sections that may show a "New {Kind}" command (SHELL-540).
    public var newItemTitle: String? {
        switch self {
        case .equipment: return "New Equipment/Area"
        case .tasks: return "New Task"
        case .procedures: return "New Procedure"
        case .vessels: return "New Vessel"
        case .board: return "New Task…"
        case .buckets: return "New Bucket…"
        case .lists: return "New List…"
        default: return nil
        }
    }

    /// ⌥⌘F target fields per section (SHELL-517 table); nil = item disabled (Calendar, Buckets).
    public var hasSearchCurrentListField: Bool {
        switch self {
        case .calendar, .buckets: return false
        default: return true
        }
    }
}
