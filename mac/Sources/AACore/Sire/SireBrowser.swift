// Spec: 12 SIRE-005…013 (search, sort, evidence / status / chapter / vessel / type filters, reset, stats footer),
//       §3.9 (ApplyFilters + the six stable sorts), §6.6 (precomputed folded search fields; OrdinalIgnoreCase without
//       diacritic folding), §7.9 vectors, Addendum TV-TAGX-BANK-2 (evidence filter counts).
import Foundation

public enum SireSortMode: String, Sendable, CaseIterable, Hashable, Codable {
    case questionNumber = "Question Number", chapter = "Chapter", shortQuestionText = "Short Question Text",
         vesselTypes = "Vessel Types", roviqSequence = "ROVIQ Sequence", questionType = "Question Type"
}

public enum SireStatusFilter: String, Sendable, CaseIterable, Hashable, Codable {
    case all = "All", inProgress = "In Progress", checked = "Checked", notApplicable = "Not Applicable",
         bookmarked = "Bookmarked", forExport = "For Export", hasTasks = "Has Tasks", noStatus = "No Status"
}

/// `Evidence category` items (the English keys are what the filter matches, A.5).
public enum SireEvidenceFilter {
    public static let all = "All"
    public static let items = ["All", "Equipment", "Document", "Procedure", "Record", "Personnel"]
}

/// Every filter input of the Filters pane. Box filters are stored as the UNticked keys, so a fresh state means
/// "every box ticked" (Windows' initial state).
public struct SireFilterCriteria: Sendable, Hashable, Codable {
    public var search: String
    public var sort: SireSortMode
    public var evidence: String
    public var status: SireStatusFilter
    public var uncheckedChapters: Set<String>
    /// Case-insensitive (upper-invariant folded) vessel-type keys.
    public var uncheckedVessels: Set<String>
    public var uncheckedTypes: Set<String>

    public init(search: String = "", sort: SireSortMode = .questionNumber, evidence: String = SireEvidenceFilter.all,
                status: SireStatusFilter = .all, uncheckedChapters: Set<String> = [], uncheckedVessels: Set<String> = [],
                uncheckedTypes: Set<String> = []) {
        self.search = search; self.sort = sort; self.evidence = evidence; self.status = status
        self.uncheckedChapters = uncheckedChapters; self.uncheckedVessels = uncheckedVessels
        self.uncheckedTypes = uncheckedTypes
    }

    /// SIRE-012 Reset: search cleared, combos at index 0, every box ticked.
    public static let reset = SireFilterCriteria()

    public static func vesselKey(_ v: String) -> String { NetText.toUpperInvariant(v) }
}

/// One checkbox row of the Chapters / Vessel types / Question type groups.
public struct SireFilterOption: Sendable, Hashable, Identifiable {
    public var key: String
    public var label: String
    public var id: String { key }
    public init(key: String, label: String) { self.key = key; self.label = label }
}

/// The precomputed browser over a loaded bank: filter options, folded search fields and the filter/sort pipeline.
public struct SireBrowser: Sendable {
    public let questions: [SireQuestion]
    public let identified: SireIdentifiedTasks
    /// `Ch {chapter}: {chapterName} ({count})`, numeric chapter order.
    public let chapterOptions: [SireFilterOption]
    /// Distinct (case-insensitive, first casing) vessel types, culture order.
    public let vesselOptions: [SireFilterOption]
    /// Distinct `QuestionTypeDisplay`, culture order.
    public let typeOptions: [SireFilterOption]
    /// Per question: the 11 searched fields, simple-upper folded (OrdinalIgnoreCase).
    let searchFields: [[[UInt16]]]
    let typeDisplays: [String]

    public init(_ contents: SireBankContents) {
        questions = contents.questions
        identified = contents.identified
        chapterOptions = contents.byChapter().map {
            SireFilterOption(key: $0.chapter, label: "Ch \($0.chapter): \($0.questions.first?.chapterName ?? "") (\($0.questions.count))")
        }
        var vOrder: [String] = []
        var vSeen = Set<String>()
        for q in questions { for v in q.vesselTypes where vSeen.insert(SireFilterCriteria.vesselKey(v)).inserted { vOrder.append(v) } }
        vesselOptions = SireOrder.sortedCulture(vOrder).map { SireFilterOption(key: SireFilterCriteria.vesselKey($0), label: $0) }
        let displays = questions.map(\.questionTypeDisplay)
        typeDisplays = displays
        var tOrder: [String] = []
        var tSeen = Set<Ordinal.Key>()
        for t in displays where tSeen.insert(Ordinal.Key(t)).inserted { tOrder.append(t) }
        typeOptions = SireOrder.sortedCulture(tOrder).map { SireFilterOption(key: $0, label: $0) }
        searchFields = questions.map { q in
            [q.questionNumber, q.shortQuestionText, q.fullQuestionText, q.objective, q.expectedEvidence,
             q.potentialNegativeObservationGrounds, q.industryGuidance, q.inspectionGuidance,
             q.suggestedInspectorActions, q.publications, q.roviqSequence].map { $0.utf16.map(NetText.simpleUpper) }
        }
    }

    // MARK: Filtering (§3.9)

    /// `ApplyFilters`: the kept questions in the chosen (stable) order.
    public func apply(_ c: SireFilterCriteria, session: SireSessionSnapshot) -> [SireQuestion] {
        let search = NetText.trim(c.search)
        let folded = search.utf16.map(NetText.simpleUpper)
        let evidencePrefix = c.evidence == SireEvidenceFilter.all ? nil : c.evidence + ":"
        var kept: [SireQuestion] = []
        for (i, q) in questions.enumerated() {
            if c.uncheckedChapters.contains(q.chapter) { continue }
            if !q.vesselTypes.isEmpty,
               !q.vesselTypes.contains(where: { !c.uncheckedVessels.contains(SireFilterCriteria.vesselKey($0)) }) { continue }
            if c.uncheckedTypes.contains(typeDisplays[i]) { continue }
            if let p = evidencePrefix, !q.evidenceTags.contains(where: { SireText.startsWithIgnoreCase(SireText.units($0), p) }) { continue }
            if !folded.isEmpty, !searchFields[i].contains(where: { Self.contains($0, folded) }) { continue }
            if c.status != .all, !Self.matchesStatus(q.questionNumber, c.status, session) { continue }
            kept.append(q)
        }
        return sort(kept, c.sort)
    }

    static func contains(_ hay: [UInt16], _ needle: [UInt16]) -> Bool {
        SireTagExtractor.containsOrdinalIgnoreCaseASCII(hay, needle)          // both folded: plain unit search
    }

    static func matchesStatus(_ n: String, _ f: SireStatusFilter, _ s: SireSessionSnapshot) -> Bool {
        switch f {
        case .all: return true
        case .inProgress: return s.status(n) == .inProgress
        case .checked: return s.status(n) == .checked
        case .notApplicable: return s.status(n) == .notApplicable
        case .bookmarked: return s.isBookmarked(n)
        case .forExport: return s.isForExport(n)
        case .hasTasks: return s.hasTasks(n)
        case .noStatus: return s.status(n) == .none
        }
    }

    /// The six sorts (stable; ties keep bank order).
    public func sort(_ qs: [SireQuestion], _ mode: SireSortMode) -> [SireQuestion] {
        func thenNumber(_ a: SireQuestion, _ b: SireQuestion, _ first: ComparisonResult) -> ComparisonResult {
            first != .orderedSame ? first : SireOrder.compareNumbers(a.questionNumber, b.questionNumber)
        }
        switch mode {
        case .questionNumber:
            return SireOrder.sortedByNumber(qs)
        case .chapter:
            return SireOrder.stableSorted(qs) { a, b in
                let ra = SireOrder.chapterRank(a.chapter), rb = SireOrder.chapterRank(b.chapter)
                return thenNumber(a, b, ra == rb ? .orderedSame : (ra < rb ? .orderedAscending : .orderedDescending))
            }
        case .shortQuestionText:
            return SireOrder.stableSorted(qs) { SireOrder.compareCulture($0.shortQuestionText, $1.shortQuestionText) }
        case .vesselTypes:
            return SireOrder.stableSorted(qs) { thenNumber($0, $1, SireOrder.compareCulture($0.vesselTypesDisplay, $1.vesselTypesDisplay)) }
        case .roviqSequence:
            return SireOrder.stableSorted(qs) { thenNumber($0, $1, SireOrder.compareCulture($0.roviqSequence, $1.roviqSequence)) }
        case .questionType:
            return SireOrder.stableSorted(qs) { thenNumber($0, $1, SireOrder.compareCulture($0.questionTypeDisplay, $1.questionTypeDisplay)) }
        }
    }

    // MARK: Stats footer (SIRE-013)

    /// The two-line footer text (two spaces between segments).
    public func statsText(session s: SireSessionSnapshot) -> String {
        "\(questions.count) questions · \(identified.totalTasks) auto-identified tasks\n"
            + "Session — ✓ \(s.count(of: .checked))  ⧗ \(s.count(of: .inProgress))  "
            + "N/A \(s.count(of: .notApplicable))  ★ \(s.bookmarks.count)  tasks \(s.tasks.count)"
    }
}
