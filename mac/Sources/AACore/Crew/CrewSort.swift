// Spec: 09 CREW-015 (sort modes, persisted enum names, Enum.TryParse), §3.7 `SortCrew`, §4.5 (`CrewSortMode`), §7.9;
//       DECISIONS 09 Q4 (stored dates read through `CrewStoredDate`).
import Foundation

/// Roster order (persisted as its C# enum name in `UiState.CrewSortMode`).
public enum CrewSortMode: Int, Sendable, CaseIterable, Identifiable {
    case signOffDate, lastName, firstName, cid, birthDate

    public var id: Int { rawValue }

    /// The C# enum name written to `Ui.CrewSortMode`.
    public var name: String {
        switch self {
        case .signOffDate: return "SignOffDate"
        case .lastName: return "LastName"
        case .firstName: return "FirstName"
        case .cid: return "Cid"
        case .birthDate: return "BirthDate"
        }
    }

    /// The combo label (CREW-015 order: Sign-off date, Last name, First name, CID, Birth date).
    public var label: String {
        switch self {
        case .signOffDate: return "Sign-off date"
        case .lastName: return "Last name"
        case .firstName: return "First name"
        case .cid: return "CID"
        case .birthDate: return "Birth date"
        }
    }

    /// `Enum.TryParse` (case-sensitive name, or an integer string; anything else → SignOffDate). An integer outside the
    /// enum's range behaves like Windows' default branch (SignOffDate).
    public init(persisted text: String?) {
        guard let raw = text.map(NetText.trim), !raw.isEmpty else { self = .signOffDate; return }
        if let m = CrewSortMode.allCases.first(where: { $0.name == raw }) { self = m; return }
        if let n = Int(raw), let m = CrewSortMode(rawValue: n) { self = m; return }
        self = .signOffDate
    }
}

public enum CrewSort {
    /// `SortCrew` — stable sorts (ties keep roster order); blank / unparseable keys sink to the bottom.
    @MainActor public static func sorted(_ crew: [CrewMember], mode: CrewSortMode, today: CivilDate) -> [CrewMember] {
        let indexed = Array(crew.enumerated())
        func oic(_ a: String, _ b: String) -> ComparisonResult { NetText.compareIgnoreCase(a, b) }
        func chain(_ results: [ComparisonResult]) -> ComparisonResult {
            results.first { $0 != .orderedSame } ?? .orderedSame
        }
        func blank(_ s: String) -> Int { NetText.isBlank(s) ? 1 : 0 }
        func cmpInt(_ a: Int, _ b: Int) -> ComparisonResult { a == b ? .orderedSame : (a < b ? .orderedAscending : .orderedDescending) }
        func cmpTicks(_ a: Int64, _ b: Int64) -> ComparisonResult {
            a == b ? .orderedSame : (a < b ? .orderedAscending : .orderedDescending)
        }

        let compare: (CrewMember, CrewMember) -> ComparisonResult
        switch mode {
        case .lastName:
            compare = { a, b in chain([cmpInt(blank(a.lastName), blank(b.lastName)), oic(a.lastName, b.lastName),
                                       oic(a.firstName, b.firstName)]) }
        case .firstName:
            compare = { a, b in chain([cmpInt(blank(a.firstName), blank(b.firstName)), oic(a.firstName, b.firstName),
                                       oic(a.lastName, b.lastName)]) }
        case .cid:
            compare = { a, b in chain([cmpInt(blank(a.employeeId), blank(b.employeeId)), oic(a.employeeId, b.employeeId),
                                       oic(a.fullName, b.fullName)]) }
        case .birthDate:
            let maxTicks = NetDateTime.maxTicks
            var ticks: [ObjectIdentifier: Int64] = [:]
            for m in crew { ticks[ObjectIdentifier(m)] = CrewStoredDate.parse(m.dateOfBirth)?.ticks ?? maxTicks }
            compare = { a, b in chain([cmpTicks(ticks[ObjectIdentifier(a)] ?? maxTicks, ticks[ObjectIdentifier(b)] ?? maxTicks),
                                       oic(a.fullName, b.fullName)]) }
        case .signOffDate:
            var days: [ObjectIdentifier: Int] = [:]
            for m in crew { days[ObjectIdentifier(m)] = CrewStoredDate.daysUntilSignOff(m, today: today) ?? Int(Int32.max) }
            compare = { a, b in chain([cmpInt(days[ObjectIdentifier(a)] ?? Int(Int32.max), days[ObjectIdentifier(b)] ?? Int(Int32.max)),
                                       oic(a.fullName, b.fullName)]) }
        }
        return indexed.sorted { x, y in
            switch compare(x.element, y.element) {
            case .orderedAscending: return true
            case .orderedDescending: return false
            case .orderedSame: return x.offset < y.offset
            }
        }.map(\.element)
    }
}
