// PLACEHOLDER(F2) — contract: ARCHITECTURE.md §6.5
// Spec: 02 REPO-150…154 (crew schedule templates, `.aasched.json` export/import, OC-41). Compiling stub created by
// F1; F2 replaces this file in place. Export/import stubs throw (nothing is written or read); the others return
// empty detached objects (ARCH §11).
import Foundation

public enum ScheduleImportError: Error, LocalizedError, Sendable {
    case notASchedule
    case parse(String)

    public var errorDescription: String? {
        // PLACEHOLDER(F2) — F2 supplies the spec wording.
        switch self {
        case .notASchedule: return "This file is not a schedule."
        case .parse(let message): return message
        }
    }
}

@MainActor public enum ScheduleService {
    public static func cloneEntry(_ e: ScheduleEntry) -> ScheduleEntry {
        // PLACEHOLDER(F2)
        ScheduleEntry()
    }

    public static func captureFromCrew(name: String, crew: CrewMember, data: AppData) -> ScheduleTemplate {
        // PLACEHOLDER(F2)
        ScheduleTemplate(name: name)
    }

    @discardableResult public static func applyToCrew(_ t: ScheduleTemplate, crew: CrewMember, replace: Bool) -> Int {
        // PLACEHOLDER(F2)
        0
    }

    /// Indented, nulls written, CRLF line ends (OC-41).
    public static func exportJSON(_ t: ScheduleTemplate) throws -> Data {
        // PLACEHOLDER(F2)
        throw ScheduleImportError.parse("Schedule export is not available yet.")
    }

    /// Fresh ids on import.
    public static func importJSON(_ data: Data) throws(ScheduleImportError) -> ScheduleTemplate {
        // PLACEHOLDER(F2)
        throw .parse("Schedule import is not available yet.")
    }
}
