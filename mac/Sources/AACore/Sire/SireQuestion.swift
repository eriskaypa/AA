// Spec: 12 SIRE-003, §3.1 (computed properties), §4.1 (bank schema: snake_case keys, absent → "" / [], null
//       tolerated, unknown keys ignored), Addendum A.4.1 (metadata, total_questions never used to validate);
//       ARCHITECTURE.md §6.8 (W-SIRE private engine types, `Sire` prefix).
import Foundation

/// One SIRE 2.0 question of the bundled OCIMF library (immutable; the session flags live in `SireState`).
public struct SireQuestion: Sendable, Hashable, Identifiable {
    public var questionNumber: String
    public var chapter: String
    public var section: String
    public var chapterName: String
    public var type: String
    public var fullQuestionText: String
    public var shortQuestionText: String
    public var vesselTypes: [String]
    public var roviqSequence: String
    public var publications: String
    public var objective: String
    public var industryGuidance: String
    public var inspectionGuidance: String
    public var suggestedInspectorActions: String
    public var expectedEvidence: String
    public var potentialNegativeObservationGrounds: String
    public var dataSource: String
    /// Smart tags (`"{Category}: {keyword}"`), culture-ordered — computed at load (SIRE-043).
    public var evidenceTags: [String]
    /// ROVIQ locations split from the sequence — computed at load (SIRE-044).
    public var roviqLocations: [String]

    public var id: String { questionNumber }

    public init(questionNumber: String = "", chapter: String = "", section: String = "", chapterName: String = "",
                type: String = "", fullQuestionText: String = "", shortQuestionText: String = "",
                vesselTypes: [String] = [], roviqSequence: String = "", publications: String = "",
                objective: String = "", industryGuidance: String = "", inspectionGuidance: String = "",
                suggestedInspectorActions: String = "", expectedEvidence: String = "",
                potentialNegativeObservationGrounds: String = "", dataSource: String = "",
                evidenceTags: [String] = [], roviqLocations: [String] = []) {
        self.questionNumber = questionNumber; self.chapter = chapter; self.section = section
        self.chapterName = chapterName; self.type = type; self.fullQuestionText = fullQuestionText
        self.shortQuestionText = shortQuestionText; self.vesselTypes = vesselTypes; self.roviqSequence = roviqSequence
        self.publications = publications; self.objective = objective; self.industryGuidance = industryGuidance
        self.inspectionGuidance = inspectionGuidance; self.suggestedInspectorActions = suggestedInspectorActions
        self.expectedEvidence = expectedEvidence
        self.potentialNegativeObservationGrounds = potentialNegativeObservationGrounds
        self.dataSource = dataSource; self.evidenceTags = evidenceTags; self.roviqLocations = roviqLocations
    }

    // MARK: Computed display properties (§3.1)

    /// `VesselTypes.Count > 0 ? string.Join(", ", VesselTypes) : "All"`.
    public var vesselTypesDisplay: String { vesselTypes.isEmpty ? "All" : vesselTypes.joined(separator: ", ") }

    /// `Ch {Chapter}: {ChapterName}`.
    public var chapterDisplay: String { "Ch \(chapter): \(chapterName)" }

    /// `data_field` → "Data Field"; `inspection_question` → "Photograph" when the full text contains "photograph"
    /// (OrdinalIgnoreCase), else "Inspection"; any other type raw.
    public var questionTypeDisplay: String {
        switch type {
        case "data_field": return "Data Field"
        case "inspection_question":
            return NetText.containsIgnoreCase(fullQuestionText, "photograph") ? "Photograph" : "Inspection"
        default: return type
        }
    }

    /// `Q {QuestionNumber} — {ShortQuestionText}` (unused by the Windows UI; kept for parity).
    public var listTitle: String { "Q \(questionNumber) — \(shortQuestionText)" }

    /// `Type == "inspection_question" && !string.IsNullOrEmpty(Objective)` (332 of 410).
    public var isDetailedQuestion: Bool { type == "inspection_question" && !objective.isEmpty }
}

/// `QuestionBank.metadata` (Addendum A.4.1). Decoded for parity, never used to validate the bank.
public struct SireBankMetadata: Sendable, Hashable {
    public var title: String
    public var version: String
    public var date: String
    public var source: String
    public var totalQuestions: Int

    public init(title: String = "", version: String = "", date: String = "", source: String = "", totalQuestions: Int = 0) {
        self.title = title; self.version = version; self.date = date; self.source = source
        self.totalQuestions = totalQuestions
    }
}

/// The offline-identified tasks per question number, in bank order (SIRE-042).
public struct SireIdentifiedTasks: Sendable, Hashable {
    /// Question numbers with at least one task, in bank order (the C# dictionary's insertion order).
    public private(set) var keys: [String]
    private var map: [Ordinal.Key: [String]]

    public init() { keys = []; map = [:] }

    /// Pairs in the given order (a duplicate key replaces the value and keeps its first position, like C#).
    public init(_ pairs: [(String, [String])]) {
        keys = []; map = [:]
        for (k, v) in pairs { self[k] = v }
    }

    public subscript(_ q: String) -> [String]? {
        get { map[Ordinal.Key(q)] }
        set {
            let k = Ordinal.Key(q)
            if let newValue {
                if map[k] == nil { keys.append(q) }
                map[k] = newValue
            } else if map.removeValue(forKey: k) != nil {
                keys.removeAll { Ordinal.equals($0, q) }
            }
        }
    }

    /// `GetIdentifiedTasks(n)`: the cached list or an empty one.
    public func tasks(for q: String) -> [String] { map[Ordinal.Key(q)] ?? [] }

    public var count: Int { keys.count }
    public var isEmpty: Bool { keys.isEmpty }
    /// `TotalIdentifiedTasks`.
    public var totalTasks: Int { map.values.reduce(0) { $0 + $1.count } }
    public var pairs: [(key: String, tasks: [String])] { keys.map { ($0, map[Ordinal.Key($0)] ?? []) } }

    public static func == (a: SireIdentifiedTasks, b: SireIdentifiedTasks) -> Bool {
        a.keys.count == b.keys.count && zip(a.pairs, b.pairs).allSatisfy { Ordinal.equals($0.key, $1.key) && $0.tasks == $1.tasks }
    }
    public func hash(into h: inout Hasher) { for p in pairs { Ordinal.hash(p.key, into: &h); h.combine(p.tasks) } }
}

/// The decoded, enriched bank (SIRE-001, §3.5): questions in bank order, metadata and identified tasks.
public struct SireBankContents: Sendable {
    public var metadata: SireBankMetadata
    public var questions: [SireQuestion]
    public var identified: SireIdentifiedTasks

    public init(metadata: SireBankMetadata = SireBankMetadata(), questions: [SireQuestion] = [],
                identified: SireIdentifiedTasks = SireIdentifiedTasks()) {
        self.metadata = metadata; self.questions = questions; self.identified = identified
    }

    /// Builds the contents from raw questions: tags, ROVIQ locations and the task engine, exactly like
    /// `SireBank.EnsureLoaded` steps 3–4.
    public static func enriched(metadata: SireBankMetadata = SireBankMetadata(), questions raw: [SireQuestion]) -> SireBankContents {
        var qs = raw
        for i in qs.indices {
            qs[i].evidenceTags = SireTagExtractor.extractTags(qs[i])
            qs[i].roviqLocations = SireTagExtractor.extractRoviqLocations(qs[i].roviqSequence)
        }
        return SireBankContents(metadata: metadata, questions: qs, identified: SireTaskIdentifier.identifyAllTasks(qs))
    }

    /// `SireBank.Get` (first match, ordinal).
    public func question(_ number: String) -> SireQuestion? {
        questions.first { Ordinal.equals($0.questionNumber, number) }
    }

    /// `ByChapter()`: groups by chapter in first-appearance order, then ordered by `int.TryParse(key) ? n : 999`
    /// (stable).
    public func byChapter() -> [(chapter: String, questions: [SireQuestion])] {
        var order: [String] = []
        var groups: [Ordinal.Key: [SireQuestion]] = [:]
        for q in questions {
            let k = Ordinal.Key(q.chapter)
            if groups[k] == nil { order.append(q.chapter); groups[k] = [] }
            groups[k]!.append(q)
        }
        let pairs = order.map { ($0, groups[Ordinal.Key($0)] ?? []) }
        return SireOrder.stableSorted(pairs) { SireOrder.chapterRank($0.0) < SireOrder.chapterRank($1.0) }
            .map { (chapter: $0.0, questions: $0.1) }
    }

    /// `InChapter(c)`: exact ordinal match, natural order.
    public func inChapter(_ chapter: String) -> [SireQuestion] {
        SireOrder.sortedByNumber(questions.filter { Ordinal.equals($0.chapter, chapter) })
    }

    /// `InSection(s)`: exact ordinal match, natural order.
    public func inSection(_ section: String) -> [SireQuestion] {
        SireOrder.sortedByNumber(questions.filter { Ordinal.equals($0.section, section) })
    }
}

// MARK: Decoding

public enum SireBankError: Error, Sendable, Equatable, LocalizedError {
    /// The resource could not be found (`Embedded SIRE question bank not found.`).
    case notFound
    /// Zero questions (`SIRE question bank is empty.`).
    case empty
    /// A JSON syntax or type error (message shown verbatim in the load-error state).
    case invalid(String)

    public var errorDescription: String? {
        switch self {
        case .notFound: return "Embedded SIRE question bank not found."
        case .empty: return "SIRE question bank is empty."
        case .invalid(let m): return m
        }
    }
}

public enum SireBankDecoder {
    /// Decodes `sire2_question_bank.json` bytes (no enrichment). Strings tolerate `null` (→ ""), absent keys
    /// default, unknown keys are ignored; a value of the wrong JSON type fails the load like System.Text.Json.
    public static func decode(_ data: Data) throws(SireBankError) -> (metadata: SireBankMetadata, questions: [SireQuestion]) {
        let root: JSONValue
        do { root = try JSONParser.parse(data) } catch { throw .invalid(String(describing: error)) }
        guard case .object(let o) = root else {
            if root.isNull { throw .empty }
            throw .invalid("The JSON value could not be converted to AA.Sire.QuestionBank. Path: $")
        }
        var metadata = SireBankMetadata()
        if let m = o["metadata"], !m.isNull {
            guard case .object(let mo) = m else { throw .invalid(typeError("AA.Sire.BankMetadata", "$.metadata")) }
            metadata.title = try string(mo, "title", "$.metadata")
            metadata.version = try string(mo, "version", "$.metadata")
            metadata.date = try string(mo, "date", "$.metadata")
            metadata.source = try string(mo, "source", "$.metadata")
            if let t = mo["total_questions"] {
                guard case .number(let n) = t, let v = n.int32Value else {
                    throw .invalid(typeError("System.Int32", "$.metadata.total_questions"))
                }
                metadata.totalQuestions = Int(v)
            }
        }
        var questions: [SireQuestion] = []
        if let qv = o["questions"], !qv.isNull {
            guard case .array(let arr) = qv else {
                throw .invalid(typeError("System.Collections.Generic.List`1[AA.Sire.SireQuestion]", "$.questions"))
            }
            questions.reserveCapacity(arr.count)
            for (i, item) in arr.enumerated() {
                let path = "$.questions[\(i)]"
                if item.isNull { throw .invalid("A null question was found. Path: \(path)") }
                guard case .object(let q) = item else { throw .invalid(typeError("AA.Sire.SireQuestion", path)) }
                questions.append(SireQuestion(
                    questionNumber: try string(q, "question_number", path),
                    chapter: try string(q, "chapter", path),
                    section: try string(q, "section", path),
                    chapterName: try string(q, "chapter_name", path),
                    type: try string(q, "type", path),
                    fullQuestionText: try string(q, "full_question_text", path),
                    shortQuestionText: try string(q, "short_question_text", path),
                    vesselTypes: try stringArray(q, "vessel_types", path),
                    roviqSequence: try string(q, "roviq_sequence", path),
                    publications: try string(q, "publications", path),
                    objective: try string(q, "objective", path),
                    industryGuidance: try string(q, "industry_guidance", path),
                    inspectionGuidance: try string(q, "inspection_guidance", path),
                    suggestedInspectorActions: try string(q, "suggested_inspector_actions", path),
                    expectedEvidence: try string(q, "expected_evidence", path),
                    potentialNegativeObservationGrounds: try string(q, "potential_negative_observation_grounds", path),
                    dataSource: try string(q, "data_source", path)))
            }
        }
        if questions.isEmpty { throw .empty }
        return (metadata, questions)
    }

    /// Decode + enrich (tags, ROVIQ, identified tasks) — the whole background part of the load.
    public static func load(_ data: Data) throws(SireBankError) -> SireBankContents {
        let d = try decode(data)
        return SireBankContents.enriched(metadata: d.metadata, questions: d.questions)
    }

    private static func typeError(_ type: String, _ path: String) -> String {
        "The JSON value could not be converted to \(type). Path: \(path)"
    }

    private static func string(_ o: JSONObject, _ key: String, _ path: String) throws(SireBankError) -> String {
        guard let v = o[key] else { return "" }
        switch v {
        case .null: return ""
        case .string(let s): return s
        default: throw .invalid(typeError("System.String", "\(path).\(key)"))
        }
    }

    private static func stringArray(_ o: JSONObject, _ key: String, _ path: String) throws(SireBankError) -> [String] {
        guard let v = o[key] else { return [] }
        switch v {
        case .null: return []
        case .array(let a):
            var out: [String] = []
            out.reserveCapacity(a.count)
            for (i, e) in a.enumerated() {
                switch e {
                case .null: out.append("")
                case .string(let s): out.append(s)
                default: throw .invalid(typeError("System.String", "\(path).\(key)[\(i)]"))
                }
            }
            return out
        default: throw .invalid(typeError("System.Collections.Generic.List`1[System.String]", "\(path).\(key)"))
        }
    }
}
