// Spec: 12 SIRE-042, §3.4 (TaskIdentifierService — bit-exact port: SplitOnBullets incl. the no-bullet fallback,
//       CollapseWhitespace, CleanFragment, IsSkippableLine, IsSubItem, EnsureCapitalized, FormatEvidenceTask,
//       FormatNegativeAsPositive, StartsWithActionVerb, NormalizeForDedup), §7.3 vectors.
import Foundation

/// Offline task-extraction engine (TaskIdentifierService.cs). Pure; UTF-16 semantics throughout.
public enum SireTaskIdentifier {
    static let skipPrefixes = [
        "Pre-Inspection", "Pre-inspection", "On-board", "On board",
        "Inspectors must not", "Inspector must not",
        "Where the vessel", "Where no defects", "Where defects",
        "In the case that", "In such cases",
        "This question will only", "Note that", "Note:",
    ]

    /// `•` U+2022, `●` U+25CF, `■` U+25A0, `▪` U+25AA.
    static let bulletChars: Set<UInt16> = [0x2022, 0x25CF, 0x25A0, 0x25AA]

    static let actionVerbs = [
        "Verify", "Check", "Review", "Confirm", "Inspect", "Examine", "Ensure", "Compare", "Test",
        "Record", "Sight", "Interview", "Observe", "Note", "Assess", "Evaluate", "Monitor", "Measure",
        "The company", "The vessel", "A printed", "Shore based", "Communications", "Records", "Evidence", "Documentary",
    ]

    enum Mode { case direct, evidence, negativeToPositive }

    /// `IdentifyAllTasks`: every detailed question in bank order with a non-empty result.
    public static func identifyAllTasks(_ questions: [SireQuestion]) -> SireIdentifiedTasks {
        var result = SireIdentifiedTasks()
        for q in questions where q.isDetailedQuestion {
            let tasks = identifyTasks(for: q)
            if !tasks.isEmpty { result[q.questionNumber] = tasks }
        }
        return result
    }

    /// `IdentifyTasksForQuestion`: SIA (Direct), EE (Evidence), negative grounds (NegativeToPositive), one shared
    /// case-insensitive `seen` set.
    public static func identifyTasks(for q: SireQuestion) -> [String] {
        identifyTasks(suggestedInspectorActions: q.suggestedInspectorActions, expectedEvidence: q.expectedEvidence,
                      negativeGrounds: q.potentialNegativeObservationGrounds)
    }

    public static func identifyTasks(suggestedInspectorActions: String, expectedEvidence: String,
                                     negativeGrounds: String) -> [String] {
        var seen = Set<[UInt16]>()
        var tasks: [String] = []
        extractBulletTasks(suggestedInspectorActions, &tasks, &seen, .direct)
        extractBulletTasks(expectedEvidence, &tasks, &seen, .evidence)
        extractBulletTasks(negativeGrounds, &tasks, &seen, .negativeToPositive)
        return tasks
    }

    static func extractBulletTasks(_ text: String, _ tasks: inout [String], _ seen: inout Set<[UInt16]>, _ mode: Mode) {
        let u = SireText.units(text)
        if SireText.isBlank(u) { return }
        for raw in splitOnBullets(u) {
            let line = cleanFragment(raw)
            if line.count < 10 { continue }
            if isSkippableLine(line) { continue }
            if isSubItem(line) { continue }
            let task: [UInt16]
            switch mode {
            case .direct: task = ensureCapitalized(line)
            case .evidence: task = formatEvidenceTask(line)
            case .negativeToPositive: task = formatNegativeAsPositive(line)
            }
            if SireText.isBlank(task) { continue }
            let key = normalizeForDedup(task)
            if key.count < 8 { continue }
            // HashSet<string>(OrdinalIgnoreCase): the key is already lower-case invariant; fold again for safety.
            if !seen.insert(key.map(NetText.simpleUpper)).inserted { continue }
            tasks.append(SireText.string(task))
        }
    }

    /// `SplitOnBullets`.
    static func splitOnBullets(_ text: [UInt16]) -> [[UInt16]] {
        var result: [[UInt16]] = []
        let parts = SireText.split(text, on: bulletChars, removeEmpty: true)
        for part in parts {
            let trimmed = SireText.trim(part)
            if !trimmed.isEmpty { result.append(collapseWhitespace(trimmed)) }
        }
        if parts.count <= 1 && !text.contains(where: { bulletChars.contains($0) }) {
            for line in SireText.split(text, on: [0x0A], removeEmpty: true) {
                let trimmed = SireText.trim(line)
                if !trimmed.isEmpty { result.append(trimmed) }
            }
        }
        return result
    }

    /// `CollapseWhitespace`: runs of space / `\n` / `\r` / `\t` → one space, then `Trim()`.
    static func collapseWhitespace(_ text: [UInt16]) -> [UInt16] {
        var out: [UInt16] = []
        out.reserveCapacity(text.count)
        var lastSpace = false
        for c in text {
            if c == 0x0A || c == 0x0D || c == 0x09 || c == 0x20 {
                if !lastSpace { out.append(0x20); lastSpace = true }
            } else {
                out.append(c); lastSpace = false
            }
        }
        return SireText.trim(out)
    }

    /// `CleanFragment`.
    static func cleanFragment(_ text: [UInt16]) -> [UInt16] {
        var t = SireText.trim(text)
        if SireText.startsWith(t, "- ") { t = SireText.trim(Array(t[2...])) }
        if t.count > 3, SireText.isDigit(t[0]), t[1] == 0x2E || t[1] == 0x29, t[2] == 0x20 { t = SireText.trim(Array(t[3...])) }
        if t.count > 3, SireText.isLetter(t[0]), t[1] == 0x2E || t[1] == 0x29, t[2] == 0x20 { t = SireText.trim(Array(t[3...])) }
        if t.last == 0x2E, !SireText.endsWith(t, "etc."), !SireText.endsWith(t, "e.g."), !SireText.endsWith(t, "i.e.") {
            t = SireText.trim(Array(t.dropLast()))
        }
        return t
    }

    /// `IsSkippableLine`.
    static func isSkippableLine(_ line: [UInt16]) -> Bool {
        for p in skipPrefixes where SireText.startsWithIgnoreCase(line, p) { return true }
        if line.count > 2, SireText.isDigit(line[0]), line[1] == 0x2E, SireText.isDigit(line[2]) || line[2] == 0x20 { return true }
        return false
    }

    /// `IsSubItem`: starts with "o ", longer than 3, third character upper-case.
    static func isSubItem(_ line: [UInt16]) -> Bool {
        SireText.startsWith(line, "o ") && line.count > 3 && SireText.isUpper(line[2])
    }

    /// `EnsureCapitalized`.
    static func ensureCapitalized(_ t: [UInt16]) -> [UInt16] {
        if t.isEmpty || SireText.isUpper(t[0]) { return t }
        var out = t
        out[0] = SireText.toUpper(t[0])
        return out
    }

    /// `FormatEvidenceTask`.
    static func formatEvidenceTask(_ t: [UInt16]) -> [UInt16] {
        if startsWithActionVerb(t) { return ensureCapitalized(t) }
        return SireText.units("Verify availability of: ") + lowerFirst(t)
    }

    static func lowerFirst(_ t: [UInt16]) -> [UInt16] {
        guard let f = t.first else { return t }
        var out = t
        out[0] = SireText.toLower(f)
        return out
    }

    /// `FormatNegativeAsPositive` — the first matching rule wins.
    static func formatNegativeAsPositive(_ text: [UInt16]) -> [UInt16] {
        let verifyThat = SireText.units("Verify that ")
        if SireText.startsWithIgnoreCase(text, "There was no ") {
            return SireText.units("Verify that there is a ") + Array(text[13...])
        }
        if SireText.startsWithIgnoreCase(text, "There were no ") {
            return SireText.units("Verify that there are ") + Array(text[14...])
        }
        if SireText.startsWithIgnoreCase(text, "No ") {
            return verifyThat + lowerFirst(text) + SireText.units(" — confirm this is not the case")
        }
        let rules: [(String, String)] = [(" was not ", " is "), (" were not ", " are "), (" had not been ", " has been "),
                                         (" had not ", " has "), (" did not ", " does ")]
        for (old, new) in rules where SireText.indexOfIgnoreCase(text, SireText.units(old)) != nil {
            return verifyThat + lowerFirst(SireText.replaceIgnoreCase(text, old, new))
        }
        return verifyThat + lowerFirst(text)
    }

    /// `StartsWithActionVerb`: case-insensitive prefix, no word boundary.
    static func startsWithActionVerb(_ t: [UInt16]) -> Bool {
        actionVerbs.contains { SireText.startsWithIgnoreCase(t, $0) }
    }

    /// `NormalizeForDedup`: `ToLowerInvariant`, keep letters/digits/spaces, `Trim()`.
    static func normalizeForDedup(_ task: [UInt16]) -> [UInt16] {
        let lowered = SireText.units(NetText.toLowerInvariant(SireText.string(task)))
        return SireText.trim(lowered.filter { SireText.isLetterOrDigit($0) || $0 == 0x20 })
    }
}
