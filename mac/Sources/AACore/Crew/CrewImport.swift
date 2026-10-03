// Spec: 09 §D CREW-030…040 (pick → read → learn → ask → convert → upsert → log → save → status → dates log →
//       post-import report), §3.7 `ImportCompas` / `AskDateOrder`, §4.7 (log entries), §7.15;
//       DECISIONS 09 Q1 (ask only when an ambiguous value was seen), Q2 (the answer takes effect for Conflicted files),
//       Q3 (re-import keeps Schedule / ScheduleVesselId); ARCHITECTURE.md §2.2 (read + convert off-main, apply on main).
import Foundation

/// Why the date-order question is asked (CREW-033).
public enum CrewDateQuestion: Sendable, Equatable {
    case unknown, conflicted

    /// The `{why}` line.
    public var why: String {
        switch self {
        case .conflicted:
            return "This file writes dates BOTH ways - some are clearly day-first and others clearly month-first, so no single reading fits all of them."
        case .unknown:
            return "Every date in this file could be read either way (nothing has a day above 12), so AA cannot tell which convention it uses."
        }
    }
}

/// The two-phase COMPAS import (learn → ask → convert) as one Sendable value: built off the main actor from the
/// parsed sheet, asked about on the main actor, converted anywhere.
public struct CrewImportSession: Sendable {
    public let fileName: String
    public let sheet: CrewCompasSheet
    public private(set) var converter: CrewConverter
    public private(set) var records: [CrewRecord] = []

    /// Learns the date convention from the whole file before any row is converted (CREW-032).
    public init(sheet: CrewCompasSheet, fileName: String, now: NetDateTime, today: CivilDate, zone: TimeZone = .current) {
        self.fileName = fileName
        self.sheet = sheet
        converter = CrewConverter(sourceFile: fileName, now: now, today: today, zone: zone, use1904: sheet.use1904)
        converter.learnDateFormat(sheet.rows)
    }

    /// DECISIONS 09 Q1: the question is asked only when the file left the convention unsettled (Unknown or
    /// Conflicted) **and** at least one value actually depends on it.
    public var question: CrewDateQuestion? {
        guard converter.dates.ambiguousCount > 0 else { return nil }
        switch converter.dateOrder {
        case .unknown: return .unknown
        case .conflicted: return .conflicted
        default: return nil
        }
    }

    /// Yes → DayFirst, No → MonthFirst (DECISIONS 09 Q2: also adopted by a Conflicted file).
    public mutating func answer(_ order: CrewDateOrder) {
        converter.applyAnswer(order)
    }

    /// Converts every row (CREW-034).
    public mutating func convertAll() {
        var out: [CrewRecord] = []
        out.reserveCapacity(sheet.rows.count)
        for row in sheet.rows { out.append(converter.convert(row)) }
        records = out
    }

    public func dateSummary() -> String { converter.dateSummary() }

    /// Σ flags over the members converted in this import.
    public var flagTotal: Int { records.reduce(0) { $0 + $1.flags.count } }

    /// The CREW-033 question body (lines joined with `\n`, the Mac platform newline). The Mac buttons are
    /// self-describing (09 §6.4), so the Yes/No/Cancel legend lines are not repeated.
    public static func questionMessage(_ q: CrewDateQuestion, fileName: String) -> String {
        [fileName, "", q.why, "", "Is a date like 03/04/2026 the 3rd of April, or the 4th of March?", "",
         "Getting this wrong shifts contract dates by weeks, so check the file if you are unsure."]
            .joined(separator: "\n")
    }

    public static let questionTitle = "Which way round are the dates?"
    public static let dayFirstButton = "Day First (03/04 = 3 April)"
    public static let monthFirstButton = "Month First (03/04 = 4 March)"
    public static let cancelButton = "Cancel Import"
}

/// The result of the upsert (CREW-035).
public struct CrewImportResult: Sendable, Equatable {
    public var memberCount: Int
    public var added: Int
    public var updated: Int
    public var flagTotal: Int
    public var dateSummary: String
    public var fileName: String
    /// The ids of the members written by this import, in file order.
    public var memberIDs: [UUID]

    public init(memberCount: Int, added: Int, updated: Int, flagTotal: Int, dateSummary: String, fileName: String,
                memberIDs: [UUID]) {
        self.memberCount = memberCount; self.added = added; self.updated = updated; self.flagTotal = flagTotal
        self.dateSummary = dateSummary; self.fileName = fileName; self.memberIDs = memberIDs
    }

    /// CREW-038 roster status line.
    public var statusText: String {
        "Imported \(memberCount) from \(fileName) (\(added) new, \(updated) updated) — \(dateSummary); \(flagTotal) review note(s)."
    }
}

@MainActor public enum CrewImport {
    public nonisolated static let openPanelTitle = "Select COMPAS crew report"
    public nonisolated static let failedTitle = "Import failed"

    /// `Could not import the COMPAS file:\n\n{message}` (CREW-040).
    public nonisolated static func failureMessage(_ message: String) -> String { "Could not import the COMPAS file:\n\n\(message)" }

    /// CREW-035/036 upsert + first log entry. For each converted member in file order the first roster member with the
    /// same `Key` (ordinal) is replaced **at its index**, the newcomer taking over its `Id`, `Checklist` and — on the Mac
    /// (DECISIONS 09 Q3) — its `Schedule` and `ScheduleVesselId`; otherwise appended. Logs
    /// `Added / "Crew import" / "{a} added, {u} updated" / file`. The caller saves.
    @discardableResult
    public static func apply(_ session: CrewImportSession, to store: AppStore) -> CrewImportResult {
        var added = 0, updated = 0
        var ids: [UUID] = []
        for record in session.records {
            let key = record.key
            if let idx = store.data.crew.firstIndex(where: { Ordinal.equals($0.key, key) }) {
                let existing = store.data.crew[idx]
                let m = record.makeMember(id: existing.id)
                m.checklist = existing.checklist
                m.schedule = existing.schedule
                m.scheduleVesselId = existing.scheduleVesselId
                store.data.crew[idx] = m
                updated += 1
                ids.append(m.id)
            } else {
                let m = record.makeMember()
                store.data.crew.append(m)
                added += 1
                ids.append(m.id)
            }
        }
        store.logAdded(kind: "Crew import", name: "\(added) added, \(updated) updated", detail: session.fileName)
        return CrewImportResult(memberCount: session.records.count, added: added, updated: updated,
                                flagTotal: session.flagTotal, dateSummary: session.dateSummary(),
                                fileName: session.fileName, memberIDs: ids)
    }

    /// CREW-037: the second log entry written after the save (autosaved by debounce).
    public static func logDates(_ result: CrewImportResult, to store: AppStore) {
        store.logAdded(kind: "Crew import dates", name: result.dateSummary, detail: result.fileName)
    }
}
