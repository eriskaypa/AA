// Spec: 01 §4.2.18, §3.26 / DATA-140 (status map, toggles, counts, Enum.TryParse emulation); 12 §4.2;
//       ARCHITECTURE.md §4.8. Unknown keys inside `Sire` are KEPT on the Mac (Windows drops them).
import Foundation
import Observation

public enum SireQuestionStatus: String, Sendable, CaseIterable {
    case none = "None", inProgress = "InProgress", checked = "Checked", notApplicable = "NotApplicable"

    /// C# enum order: None 0, InProgress 1, Checked 2, NotApplicable 3.
    static let byNumber: [Int: SireQuestionStatus] = [0: .none, 1: .inProgress, 2: .checked, 3: .notApplicable]

    /// C# `Enum.TryParse<QuestionStatus>` (case-sensitive name, or an integer string of a defined value);
    /// anything else → `.none`.
    public static func parse(_ text: String?) -> SireQuestionStatus {
        guard let text else { return .none }
        let t = NetText.trim(text)                                 // Enum.TryParse ignores surrounding white space
        if let s = SireQuestionStatus(rawValue: t) { return s }
        if let n = Int(t.hasPrefix("+") ? String(t.dropFirst()) : t), let s = byNumber[n] { return s }
        return .none
    }
}

@MainActor @Observable
public final class SireTask: JSONModel, @MainActor Identifiable {
    public var id: UUID
    public var questionNumber: String
    public var text: String
    public var isCompleted: Bool
    public var createdAt: NetDateTime
    @ObservationIgnored public var extra = JSONObject()

    public static let jsonKeys = ["Id", "QuestionNumber", "Text", "IsCompleted", "CreatedAt"]

    public init(id: UUID = UUID(), questionNumber: String = "", text: String = "", isCompleted: Bool = false,
                createdAt: NetDateTime = .now()) {
        self.id = id; self.questionNumber = questionNumber; self.text = text; self.isCompleted = isCompleted
        self.createdAt = createdAt
    }

    public init(json o: JSONObject, context c: JSONDecodeContext) throws(JSONModelError) {
        let r = JSONFieldReader(o, context: c, type: "SireTask")
        id = try r.guid("Id") ?? c.newGuid()
        questionNumber = try r.string("QuestionNumber") ?? ""
        text = try r.string("Text") ?? ""
        isCompleted = try r.bool("IsCompleted") ?? false
        createdAt = try r.date("CreatedAt") ?? c.clock.now()
        extra = r.unknownMembers(knownKeys: Self.jsonKeys)
    }

    public func toJSON(options: JSONEncodeOptions = .dataFile) -> JSONObject {
        var w = JSONObjectBuilder(options)
        w.guid("Id", id); w.string("QuestionNumber", questionNumber); w.string("Text", text)
        w.bool("IsCompleted", isCompleted); w.date("CreatedAt", createdAt)
        return w.build(appending: extra)
    }
}

@MainActor @Observable
public final class SireState: JSONModel {
    /// Question number → "InProgress" / "Checked" / "NotApplicable".
    public var questionStatuses: OrderedMap<String>
    public var bookmarks: [String]
    public var forExport: [String]
    public var tasks: [SireTask]
    /// Question number → Section XAML.
    public var questionBodies: OrderedMap<String>
    @ObservationIgnored public var extra = JSONObject()

    public static let jsonKeys = ["QuestionStatuses", "Bookmarks", "ForExport", "Tasks", "QuestionBodies"]

    public init() {
        questionStatuses = OrderedMap(); bookmarks = []; forExport = []; tasks = []; questionBodies = OrderedMap()
    }

    public init(json o: JSONObject, context c: JSONDecodeContext) throws(JSONModelError) {
        let r = JSONFieldReader(o, context: c, type: "SireState")
        questionStatuses = try r.stringMap("QuestionStatuses") ?? OrderedMap()
        bookmarks = try r.stringArray("Bookmarks") ?? []
        forExport = try r.stringArray("ForExport") ?? []
        tasks = try r.modelArray("Tasks", SireTask.self) ?? []
        questionBodies = try r.stringMap("QuestionBodies") ?? OrderedMap()
        extra = r.unknownMembers(knownKeys: Self.jsonKeys)
    }

    public func toJSON(options: JSONEncodeOptions = .dataFile) -> JSONObject {
        var w = JSONObjectBuilder(options)
        w.stringMap("QuestionStatuses", questionStatuses); w.stringArray("Bookmarks", bookmarks)
        w.stringArray("ForExport", forExport); w.modelArray("Tasks", tasks)
        w.stringMap("QuestionBodies", questionBodies)
        return w.build(appending: extra)
    }

    // MARK: Helpers (SireState.cs, DATA-140)

    /// `Enum.TryParse` of the stored text; missing/unparseable → `.none`. The stored text is never rewritten.
    public func status(for q: String) -> SireQuestionStatus { SireQuestionStatus.parse(questionStatuses[q]) }

    /// `.none` removes the key; otherwise stores the enum name.
    public func setStatus(_ s: SireQuestionStatus, for q: String) {
        if s == .none { questionStatuses[q] = nil } else { questionStatuses[q] = s.rawValue }
    }

    /// Count of stored values equal (ordinal) to the status name.
    public func count(of s: SireQuestionStatus) -> Int {
        questionStatuses.values.filter { Ordinal.equals($0, s.rawValue) }.count
    }

    public func isBookmarked(_ q: String) -> Bool { bookmarks.contains { Ordinal.equals($0, q) } }
    public func toggleBookmark(_ q: String) {
        if let i = bookmarks.firstIndex(where: { Ordinal.equals($0, q) }) { bookmarks.remove(at: i) } else { bookmarks.append(q) }
    }

    public func isForExport(_ q: String) -> Bool { forExport.contains { Ordinal.equals($0, q) } }
    public func toggleForExport(_ q: String) {
        if let i = forExport.firstIndex(where: { Ordinal.equals($0, q) }) { forExport.remove(at: i) } else { forExport.append(q) }
    }

    /// Tasks with `QuestionNumber == q` (ordinal), list order.
    public func tasks(for q: String) -> [SireTask] { tasks.filter { Ordinal.equals($0.questionNumber, q) } }
    public var totalTaskCount: Int { tasks.count }
    public var completedTaskCount: Int { tasks.filter(\.isCompleted).count }

    /// `QuestionNumberComparer`: split on `.`, each part an int (non-numeric → 0), component-wise, missing = 0.
    public nonisolated static func compareQuestionNumbers(_ a: String, _ b: String) -> ComparisonResult {
        let pa = a.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) ?? 0 }
        let pb = b.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0, y = i < pb.count ? pb[i] : 0
            if x != y { return x < y ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
    }
}
