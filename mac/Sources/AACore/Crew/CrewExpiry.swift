// Spec: 09 CREW-002 (badge), CREW-050 (contract expiries report), CREW-051 (expiry text & colour), CREW-052/053
//       (status, thresholds), §7.8; 03 SHELL-030/133 (badge and reminder consumers); DECISIONS 09 Q4 (strict reading,
//       `CrewStoredDate`); ARCHITECTURE.md §6.8.
import Foundation

/// The five fixed expiry colours (identical in light and dark, CREW-051): the UI maps them to `AAColor.Status`.
public enum CrewExpiryTone: Sendable, Equatable {
    /// `#8A8A8A` (no parseable sign-off date).
    case neutral
    /// `#D45050` (ended or signs off today).
    case red
    /// `#E8890C` (1…30 days).
    case orange
    /// `#C9A227` (31…60 days).
    case amber
    /// `#2E9E5B` (more than 60 days).
    case green
}

public enum CrewExpiry {
    public static let warnDays = 60, criticalDays = 30

    /// CREW-002: crew whose `DaysUntilSignOff(today)` is known and ≤ 60 (overdue included).
    @MainActor public static func expiringCount(_ crew: [CrewMember], today: CivilDate) -> Int {
        crew.reduce(0) { n, m in
            guard let d = CrewStoredDate.daysUntilSignOff(m, today: today), d <= warnDays else { return n }
            return n + 1
        }
    }

    /// `"Crew  ⚠ n"` (two spaces) when n > 0, else `"Crew"` (CREW-002; also the accessibility/tooltip text).
    public static func badgeText(_ n: Int) -> String {
        n > 0 ? "Crew  \u{26A0} \(n)" : "Crew"
    }

    // MARK: CREW-051

    /// The roster/banner expiry line and its tone for `d = DaysUntilSignOff(today)`.
    @MainActor public static func expiry(_ m: CrewMember, today: CivilDate) -> (text: String, tone: CrewExpiryTone) {
        expiry(days: CrewStoredDate.daysUntilSignOff(m, today: today), signOffDate: m.signOffDate)
    }

    public static func expiry(days: Int?, signOffDate date: String) -> (text: String, tone: CrewExpiryTone) {
        guard let d = days else { return ("", .neutral) }
        if d < 0 { return ("\u{26A0} Contract ended \(-d)d ago  (\(date))", .red) }
        if d == 0 { return ("\u{26A0} Signs off today  (\(date))", .red) }
        if d <= criticalDays { return ("\u{26A0} Signs off in \(d)d  (\(date))", .orange) }
        if d <= warnDays { return ("Signs off in \(d)d  (\(date))", .amber) }
        return ("Signs off in \(d)d  (\(date))", .green)
    }

    /// CREW-021: the banner body when the sign-off date is blank or unreadable.
    public static let noSignOffDate = "No sign-off date on file — contract expiry can't be tracked."

    // MARK: CREW-050

    public static let reportTitle = "Contract expiries"

    /// `"No crew contracts are overdue or due within 60 days."` (interactive only).
    public static var noneMessage: String { "No crew contracts are overdue or due within \(warnDays) days." }

    /// Members with a known sign-off ≤ 60 days away, most overdue first (stable).
    @MainActor public static func due(_ crew: [CrewMember], today: CivilDate) -> [(member: CrewMember, days: Int)] {
        let pairs = crew.compactMap { m -> (member: CrewMember, days: Int)? in
            guard let d = CrewStoredDate.daysUntilSignOff(m, today: today), d <= warnDays else { return nil }
            return (m, d)
        }
        return pairs.enumerated().sorted { a, b in
            a.element.days != b.element.days ? a.element.days < b.element.days : a.offset < b.offset
        }.map(\.element)
    }

    /// `"  •  {FullName}  ({RankDisplay})  —  {SignOffDate}  [{when}]"`.
    @MainActor public static func reportLine(_ m: CrewMember, days d: Int) -> String {
        let when = d < 0 ? "OVERDUE by \(-d)d" : d == 0 ? "signs off TODAY" : "in \(d)d"
        return "  \u{2022}  \(m.fullName)  (\(rankDisplay(m)))  \u{2014}  \(m.signOffDate)  [\(when)]"
    }

    /// The warning body: `"{n} crew contract(s) overdue or due within 60 days:\n\n" + lines joined with "\n"`.
    @MainActor public static func reportMessage(_ due: [(member: CrewMember, days: Int)]) -> String {
        "\(due.count) crew contract(s) overdue or due within \(warnDays) days:\n\n"
            + due.map { reportLine($0.member, days: $0.days) }.joined(separator: "\n")
    }

    /// `RankDisplay` = Rank when RankCode is blank, else `"{Rank} ({RankCode})"`.
    @MainActor public static func rankDisplay(_ m: CrewMember) -> String {
        NetText.isBlank(m.rankCode) ? m.rank : "\(m.rank) (\(m.rankCode))"
    }
}
