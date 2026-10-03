// Spec: 09 §6.4 (Mac layout: roster + card split; the crew table window), CREW-103 (WPF auto-sized the grid columns);
//       ARCHITECTURE.md §7.2 (HSplitView inside sections). The view-free geometry of the Crew section and the crew
//       table, kept here so the sizing rules are unit-tested (the views in Sources/AA/Crew read these values).
import Foundation

/// Crew section geometry (Stage V round 2, V2-J5). With the sidebar at its ideal width the section fits the main
/// window's minimum — 228 + 1 + 240 + 1 + 340 = 810 ≤ 860 pt — so the roster, the card, Edit… and Open Checklist… stay
/// reachable at every size the main window allows.
public enum CrewLayout {
    public static let rosterMinWidth: CGFloat = 240
    public static let rosterIdealWidth: CGFloat = 340
    public static let rosterMaxWidth: CGFloat = 520
    public static let cardMinWidth: CGFloat = 340
    /// The leading padding that lays the section's split view out inside the sidebar's safe area (see `CrewTabView`).
    public static let splitLeadingInset: CGFloat = 1
    public static let dividerWidth: CGFloat = 1
    /// The main window's minimum width and the sidebar column's ideal width (`MainWindowView`, owned by W-SHELL).
    public static let mainWindowMinWidth: CGFloat = 860
    public static let sidebarIdealWidth: CGFloat = 228

    /// The narrowest the Crew section's content can be laid out (both pane minimums, the divider, the leading inset).
    public static var sectionMinWidth: CGFloat { splitLeadingInset + rosterMinWidth + dividerWidth + cardMinWidth }

    /// Whether the section fits beside a sidebar of `sidebar` points in a window `window` points wide.
    public static func fits(window: CGFloat, sidebar: CGFloat = sidebarIdealWidth) -> Bool {
        sidebar + sectionMinWidth <= window
    }
}

/// CREW-103 starting column widths of the crew table window. WPF's DataGrid auto-sized every column to its header and
/// cells; the Mac sizes each column's ideal width from the measured header (the window's aaMono 13) and the widest
/// cell (aaMono 12), never below the column's base width, so no default header or cell starts truncated.
public enum CrewTableSizing {
    /// Space a header needs beyond its text (cell insets plus the sort-indicator gap).
    public static let headerChrome: CGFloat = 22
    /// Space a cell needs beyond its text (cell insets).
    public static let cellChrome: CGFloat = 14
    /// A cell longer than this is not allowed to widen its column further (a free-text value keeps the column sane;
    /// the column stays resizable).
    public static let maxIdealWidth: CGFloat = 320

    /// The floor of each column (the pre-measurement starting widths).
    public static func baseWidth(_ key: String) -> CGFloat {
        switch key {
        case "FullName", "Company", "Vessel", "SourceFile": return 150
        case "Rank": return 110
        case "PlaceOfBirth", "NokRelationship", "NokFirstName", "NokLastName": return 120
        case "LastName", "FirstName", "MiddleName": return 96
        case "Nationality", "ImportedAt": return 92
        case "ContractStatus": return 112
        case "Cid", "Gender", "Height", "EyesColor", "HairColor", "UserType", "ChecklistCount", "RankCode",
             "DaysUntilSignOff", "SignedOnOff": return 60
        default: return 100
        }
    }

    /// `max(base, header + headerChrome, widest cell + cellChrome)`, rounded up, capped at `maxIdealWidth` (but
    /// never below what the header needs).
    public static func idealWidth(key: String, header: String, cells: [String],
                                  measureHeader: (String) -> CGFloat, measureCell: (String) -> CGFloat) -> CGFloat {
        let headerNeed = (measureHeader(header) + headerChrome).rounded(.up)
        let widest = cells.reduce(CGFloat(0)) { max($0, $1.isEmpty ? 0 : measureCell($1)) }
        let cellNeed = widest > 0 ? min((widest + cellChrome).rounded(.up), maxIdealWidth) : 0
        return max(baseWidth(key), headerNeed, cellNeed)
    }
}
