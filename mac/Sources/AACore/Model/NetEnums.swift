// Spec: 01 §4.2.19 (model enums persisted as Int32 numbers; unknown values round-trip), 04 Q-G / DECISIONS
//       (friendly display labels, display-only); ARCHITECTURE.md §3.7.
import Foundation

public protocol NetIntEnum: RawRepresentable, Hashable, Sendable, CustomStringConvertible where RawValue == Int {
    /// Any Int is accepted; unknown values round-trip unchanged.
    init(rawValue: Int)
    /// Enum names as C# prints them.
    static var names: [Int: String] { get }
}

public extension NetIntEnum {
    /// The C# enum name (`Todo`, `InProgress`, …) or the number for an undefined value.
    var name: String { Self.names[rawValue] ?? String(rawValue) }
    var description: String { name }
}

public struct FileKind: NetIntEnum {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let document = FileKind(rawValue: 0), image = FileKind(rawValue: 1), video = FileKind(rawValue: 2),
                      link = FileKind(rawValue: 3), other = FileKind(rawValue: 4)
    public static let names: [Int: String] = [0: "Document", 1: "Image", 2: "Video", 3: "Link", 4: "Other"]
}

public struct ItemKind: NetIntEnum {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let equipment = ItemKind(rawValue: 0), task = ItemKind(rawValue: 1),
                      procedure = ItemKind(rawValue: 2), vessel = ItemKind(rawValue: 3)
    public static let names: [Int: String] = [0: "Equipment", 1: "Task", 2: "Procedure", 3: "Vessel"]
    public static let allKinds: [ItemKind] = [.equipment, .task, .procedure, .vessel]
}

public struct RecurrenceKind: NetIntEnum {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let none = RecurrenceKind(rawValue: 0), daily = RecurrenceKind(rawValue: 1),
                      weekly = RecurrenceKind(rawValue: 2), monthly = RecurrenceKind(rawValue: 3),
                      yearly = RecurrenceKind(rawValue: 4)
    public static let names: [Int: String] = [0: "None", 1: "Daily", 2: "Weekly", 3: "Monthly", 4: "Yearly"]
    public static let allKinds: [RecurrenceKind] = [.none, .daily, .weekly, .monthly, .yearly]
    /// Display-only label (DECISIONS 04 Q-G); the stored integer never changes.
    public var friendlyLabel: String { name }
}

public struct WorkStatus: NetIntEnum {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let todo = WorkStatus(rawValue: 0), inProgress = WorkStatus(rawValue: 1),
                      blocked = WorkStatus(rawValue: 2), done = WorkStatus(rawValue: 3)
    public static let names: [Int: String] = [0: "Todo", 1: "InProgress", 2: "Blocked", 3: "Done"]
    public static let allStatuses: [WorkStatus] = [.todo, .inProgress, .blocked, .done]
    /// Display-only label (DECISIONS 04 Q-G): "To Do", "In Progress", "Blocked", "Done".
    public var friendlyLabel: String {
        switch rawValue {
        case 0: return "To Do"
        case 1: return "In Progress"
        case 2: return "Blocked"
        case 3: return "Done"
        default: return name
        }
    }
}

public struct ScheduleKind: NetIntEnum {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let note = ScheduleKind(rawValue: 0), task = ScheduleKind(rawValue: 1),
                      procedure = ScheduleKind(rawValue: 2), equipment = ScheduleKind(rawValue: 3)
    public static let names: [Int: String] = [0: "Note", 1: "Task", 2: "Procedure", 3: "Equipment"]
}

public struct CrewFlagSeverity: NetIntEnum {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let info = CrewFlagSeverity(rawValue: 0), warning = CrewFlagSeverity(rawValue: 1),
                      error = CrewFlagSeverity(rawValue: 2)
    public static let names: [Int: String] = [0: "Info", 1: "Warning", 2: "Error"]
}
