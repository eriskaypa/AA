// Spec: 09 §G CREW-070…074 (editor: Details form, text rows trimmed, date rows with the free-text box as the source of
//       truth, Save applies in form order, Cancel discards), §3.8; DECISIONS 09 Q4 (an ambiguous day/month text is kept
//       verbatim instead of being silently read month-first).
import Foundation

/// One Details row.
public struct CrewEditorField: Sendable, Equatable, Identifiable {
    /// The `CrewMember` JSON key the row edits.
    public let key: String
    public let label: String
    public let isDate: Bool
    /// The bold accent `Sign-off date  (contract)` label.
    public let emphasised: Bool
    public var id: String { key }

    public init(key: String, label: String, isDate: Bool = false, emphasised: Bool = false) {
        self.key = key; self.label = label; self.isDate = isDate; self.emphasised = emphasised
    }
}

public struct CrewEditorSection: Sendable, Equatable, Identifiable {
    public let heading: String
    public let fields: [CrewEditorField]
    public var id: String { heading }
    public init(heading: String, fields: [CrewEditorField]) { self.heading = heading; self.fields = fields }
}

public enum CrewEditorForm {
    public static let windowTitle = "Edit crew member"
    public static let detailsHint = "Change any field and click Save. Dates use a calendar picker. Cancel discards changes to these details."
    public static let checklistHint = "This crew member's personal checklist. Give an item a due date (in its full editor) and it shows in the \u{1F4CC} due-dates window and the Calendar. Checklist changes save immediately — they are not undone by Cancel."
    public static let scheduleHint = "A timeline for this crew member — add tasks, procedures, equipment or free notes on a date. Save/export the schedule to reuse it on any crew, and link it to a vessel. Changes save immediately."
    public static let dateTextHelp = "Free-text form of the date (kept in sync with the picker)."
    public static let checklistLogKind = "Crew checklist item"

    /// `Edit crew member — {FullName or (unnamed)}`.
    public static func heading(fullName: String) -> String {
        "Edit crew member — " + (fullName.isEmpty ? CrewRoster.unnamed : fullName)
    }

    /// The Details form in order (CREW-071).
    public static let sections: [CrewEditorSection] = [
        CrewEditorSection(heading: "Identity", fields: [
            CrewEditorField(key: "FirstName", label: "First name"),
            CrewEditorField(key: "MiddleName", label: "Middle name"),
            CrewEditorField(key: "LastName", label: "Last name"),
            CrewEditorField(key: "EmployeeId", label: "Employee ID"),
            CrewEditorField(key: "Nationality", label: "Nationality"),
            CrewEditorField(key: "DateOfBirth", label: "Date of birth", isDate: true),
            CrewEditorField(key: "PlaceOfBirth", label: "Place of birth"),
            CrewEditorField(key: "Gender", label: "Gender"),
        ]),
        CrewEditorSection(heading: "Employment & Sign-On / Sign-Off", fields: [
            CrewEditorField(key: "Rank", label: "Rank"),
            CrewEditorField(key: "RankCode", label: "Rank code"),
            CrewEditorField(key: "SignedOnOff", label: "Status (On/Off)"),
            CrewEditorField(key: "Company", label: "Company"),
            CrewEditorField(key: "Vessel", label: "Vessel"),
            CrewEditorField(key: "SignOnDate", label: "Sign-on date", isDate: true),
            CrewEditorField(key: "SignOnPort", label: "Sign-on port"),
            CrewEditorField(key: "SignOffDate", label: "Sign-off date  (contract)", isDate: true, emphasised: true),
            CrewEditorField(key: "SignOffPort", label: "Sign-off port"),
        ]),
        CrewEditorSection(heading: "Travel Documents", fields: [
            CrewEditorField(key: "PassportNumber", label: "Passport no."),
            CrewEditorField(key: "PassportIssued", label: "Passport issued", isDate: true),
            CrewEditorField(key: "PassportExpiry", label: "Passport expiry", isDate: true),
            CrewEditorField(key: "SeamansBookNumber", label: "Seaman's book no."),
            CrewEditorField(key: "SeamansBookIssued", label: "Seaman's book issued", isDate: true),
            CrewEditorField(key: "SeamansBookExpiry", label: "Seaman's book expiry", isDate: true),
        ]),
        CrewEditorSection(heading: "Certificates & Medical", fields: [
            CrewEditorField(key: "CocNumber", label: "CoC number"),
            CrewEditorField(key: "CocIssue", label: "CoC issued", isDate: true),
            CrewEditorField(key: "CocExpiry", label: "CoC expiry", isDate: true),
            CrewEditorField(key: "HealthCertExpiry", label: "Health cert. expiry", isDate: true),
        ]),
        CrewEditorSection(heading: "Physical", fields: [
            CrewEditorField(key: "Height", label: "Height (cm)"),
            CrewEditorField(key: "EyesColor", label: "Eyes"),
            CrewEditorField(key: "HairColor", label: "Hair"),
        ]),
        CrewEditorSection(heading: "Next of Kin", fields: [
            CrewEditorField(key: "NokFirstName", label: "First name"),
            CrewEditorField(key: "NokLastName", label: "Last name"),
            CrewEditorField(key: "NokRelationship", label: "Relationship"),
        ]),
    ]

    public static var allFields: [CrewEditorField] { sections.flatMap(\.fields) }

    /// The draft text of every row, pre-filled with the stored values (dates verbatim).
    @MainActor public static func draft(of m: CrewMember) -> [String: String] {
        var d: [String: String] = [:]
        for f in allFields { d[f.key] = m.stringField(f.key) }
        return d
    }

    /// The picker's initial value for a stored date (may be nil — then the picker is empty, the text kept).
    public static func pickerDate(_ text: String) -> CivilDate? { CrewStoredDate.civil(NetText.trim(text)) }

    /// What Save stores for a date row: `t = text.Trim()`; parseable → `yyyy-MM-dd` (time dropped), else `t` verbatim
    /// (unparseable legacy text survives; an emptied box stores ""; DECISIONS 09 Q4: an ambiguous `03/04/2026` is
    /// not parseable here).
    public static func storedDate(_ text: String) -> String {
        let t = NetText.trim(text)
        if let d = CrewStoredDate.civil(t) { return d.iso }
        return t
    }

    /// Mac-only inline hint under a date row whose text cannot be tracked.
    public static func dateHint(_ text: String) -> String? {
        let t = NetText.trim(text)
        if t.isEmpty || CrewStoredDate.civil(t) != nil { return nil }
        if CrewStoredDate.isAmbiguous(t) {
            return "Day and month could be either way round — pick the date in the calendar or type yyyy-MM-dd."
        }
        return "Not a date AA recognises — it is kept as typed."
    }

    /// CREW-074 Save: every row applied in form order (text trimmed; dates per `storedDate`).
    @MainActor public static func apply(_ draft: [String: String], to m: CrewMember) {
        for f in allFields { applyRow(f, draft[f.key] ?? "", to: m) }
    }

    /// CREW-074 Save with DECISIONS 06 R1 ("never orphan edits"): `original` is the draft the form was filled with.
    /// A row the user left untouched (`draft == original`) whose stored value has changed since — a reload, shared-save
    /// pull, Flash Sync apply or Drive import replaced the member while the editor was open — keeps the newer stored
    /// value instead of writing the stale pre-reload text back. Every other row is applied exactly as `apply(_:to:)`
    /// (so an untouched row whose stored value did not change is still trimmed / normalised, as on Windows).
    /// Returns the keys that were kept because they changed under the editor.
    @discardableResult
    @MainActor public static func apply(_ draft: [String: String], original: [String: String],
                                        to m: CrewMember) -> [String] {
        var kept: [String] = []
        for f in allFields {
            let text = draft[f.key] ?? ""
            let base = original[f.key] ?? ""
            if Ordinal.equals(text, base), !Ordinal.equals(m.stringField(f.key), base) {
                kept.append(f.key)
                continue
            }
            applyRow(f, text, to: m)
        }
        return kept
    }

    /// After the store was replaced under an open editor: rows the user has not touched take the member's fresh
    /// values, edited rows keep the user's text, and the baseline becomes the fresh stored values.
    @MainActor public static func rebase(draft: inout [String: String], original: inout [String: String],
                                         onto m: CrewMember) {
        let fresh = self.draft(of: m)
        for f in allFields where Ordinal.equals(draft[f.key] ?? "", original[f.key] ?? "") {
            draft[f.key] = fresh[f.key] ?? ""
        }
        original = fresh
    }

    @MainActor private static func applyRow(_ f: CrewEditorField, _ text: String, to m: CrewMember) {
        let v = f.isDate ? storedDate(text) : NetText.trim(text)
        if !Ordinal.equals(m.stringField(f.key), v) { m.setStringField(f.key, v) }
    }
}
