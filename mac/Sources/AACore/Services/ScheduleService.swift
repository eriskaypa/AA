// Spec: 02 §2.O, §3.10 (REPO-150…154), 06 BUILD-A12…A14, §4.5, §7.11; OC-41 (`.aasched.json` = the 01 JSON writer
//       indented, 2-space indent, `"Key": value`, nulls written, default escaping, CRLF; declared keys only).
import Foundation

public enum ScheduleImportError: Error, LocalizedError, Sendable {
    /// The file's JSON is `null` (STJ `Deserialize` returned null).
    case notASchedule
    /// Unreadable JSON or a value of the wrong type (the parser / decoder message).
    case parse(String)

    public var errorDescription: String? {
        switch self {
        case .notASchedule: return "This file is not a valid schedule."
        case .parse(let message): return message
        }
    }
}

@MainActor public enum ScheduleService {
    /// REPO-150: a new entry with a NEW id, `Done = false`, and copies of Title, Kind, RefId, Date, Time, EndDate,
    /// EndTime and Notes.
    public static func cloneEntry(_ e: ScheduleEntry) -> ScheduleEntry {
        ScheduleEntry(title: e.title, kind: e.kind, refId: e.refId, date: e.date, time: e.time,
                      endDate: e.endDate, endTime: e.endTime, done: false, notes: e.notes)
    }

    /// REPO-151 / BUILD-A12: Name trimmed, VesselId = the crew's schedule vessel, VesselName = that vessel's current
    /// name (`""` when unset or not found), entries = clones of the crew schedule in order.
    public static func captureFromCrew(name: String, crew: CrewMember, data: AppData) -> ScheduleTemplate {
        let vesselName = crew.scheduleVesselId.flatMap { vid in data.vessels.first(where: { $0.id == vid })?.name } ?? ""
        return ScheduleTemplate(name: NetText.trim(name), vesselId: crew.scheduleVesselId, vesselName: vesselName,
                                entries: crew.schedule.map(cloneEntry))
    }

    /// REPO-152 / BUILD-A13: clears the crew schedule when `replace`, appends clones of every entry, and — only when
    /// the template has a VesselId — sets it as the crew's schedule vessel (even if that vessel is not local).
    /// Returns the entry count.
    @discardableResult public static func applyToCrew(_ t: ScheduleTemplate, crew: CrewMember, replace: Bool) -> Int {
        if replace { crew.schedule.removeAll() }
        crew.schedule.append(contentsOf: t.entries.map(cloneEntry))
        if let v = t.vesselId { crew.scheduleVesselId = v }
        return t.entries.count
    }

    /// REPO-153 / BUILD-A14: the template as System.Text.Json default-options indented JSON — PascalCase, enums as
    /// integers, nulls WRITTEN (`"VesselId": null`, `"RefId": null`), default escaping, 2-space indent, CRLF, no
    /// BOM, declared keys only (unknown members kept in memory are not exported).
    public static func exportJSON(_ t: ScheduleTemplate) throws -> Data {
        try JSONWriter.data(.object(t.toJSON(options: .aasched)), options: .aaschedIndented)
    }

    /// REPO-154 / BUILD-A14: parses (BOM, LF or CRLF, escaped or raw UTF-8 all accepted; case-sensitive keys;
    /// unknown members ignored); JSON `null` → `.notASchedule`; then assigns a fresh template Id and fresh entry
    /// ids, keeping everything else (CreatedUtc, VesselId, VesselName, Done flags) as in the file.
    public static func importJSON(_ data: Data) throws(ScheduleImportError) -> ScheduleTemplate {
        let root: JSONValue
        do {
            root = try JSONParser.parse(data)
        } catch {
            throw .parse(svcParseMessage(error))
        }
        let object: JSONObject
        switch root {
        case .null: throw .notASchedule
        case .object(let o): object = o
        default: throw .parse("The JSON value could not be converted to a schedule.")
        }
        let t: ScheduleTemplate
        do {
            t = try ScheduleTemplate(json: object, context: .standard)
        } catch {
            throw .parse(error.description)
        }
        t.id = UUID()
        for e in t.entries { e.id = UUID() }
        return t
    }

    private static func svcParseMessage(_ e: JSONParseError) -> String {
        switch e {
        case .invalid(let offset, let reason): return "The file is not valid JSON (\(reason) at byte \(offset))."
        case .tooDeep(let limit): return "The file is nested more than \(limit) levels deep."
        case .invalidUTF8(let offset): return "The file is not valid UTF-8 (byte \(offset))."
        }
    }
}
