// Spec: 12 SIRE-001…035, SIRE-040 (data-model swap: re-bind, re-filter (Q-10 fix), keep the selection, reload the body
//       without flushing), §3.9, §3.11, §3.12 (page state machine), §6.2, §6.10, §6.11, Q-3 (multi-selection, primary =
//       last clicked), Q-4 (AI result bound to the originating question), Q-7 (only status changes re-filter),
//       DECISIONS 12 (filter state remembered per Mac in UserDefaults, never in data.json); VIEW-212 rows 23–25
//       (candidate picker returns candidate order; kind and export pickers are single-select).
import AppKit
import Observation
import SwiftUI
import AACore

/// What the Filters pane remembers on this Mac (`aa.sire.filters`).
struct SirePersistedFilters: Codable, Equatable {
    var criteria: SireFilterCriteria
    var filterWidth: Double? = nil
    var listWidth: Double? = nil
    var chaptersExpanded = true
    var vesselsExpanded = false
    var typesExpanded = false
    var filterPaneVisible = true
}

extension SirePersistedFilters {
    func withWidths(_ f: CGFloat, _ l: CGFloat) -> SirePersistedFilters {
        var c = self
        c.filterWidth = Double(f); c.listWidth = Double(l)
        return c
    }
}

extension MacPreferences.Key {
    static let sireFilters = MacPreferences.Key("aa.sire.filters")
}

/// The SIRE tab's state (one per process: the tab lives in the single main window and the Tools-menu export reads
/// its current list).
@MainActor @Observable
final class SireViewModel {
    static let shared = SireViewModel()

    @ObservationIgnored private(set) weak var env: AppEnvironment?
    @ObservationIgnored private var subscriptions: [EventSubscription] = []
    @ObservationIgnored private var flushToken: EditorFlushCenter.Token?
    @ObservationIgnored private var restoring = false

    /// The loaded bank as a browser (nil until the first successful load).
    private(set) var browser: SireBrowser?
    /// Filter inputs; every change re-filters (SIRE-005…012) and is remembered per Mac.
    var criteria = SireFilterCriteria() {
        didSet {
            guard criteria != oldValue else { return }
            applyFilters()
            persistFilters()
        }
    }
    var chaptersExpanded = true { didSet { persistFilters() } }
    var vesselsExpanded = false { didSet { persistFilters() } }
    var typesExpanded = false { didSet { persistFilters() } }
    var filterPaneVisible = true { didSet { persistFilters() } }
    /// Pane widths (SIRE-004 250 / 360 on Windows; remembered per Mac — DECISIONS 12).
    var filterWidth: CGFloat = 250
    var listWidth: CGFloat = 360
    static let filterRange: ClosedRange<CGFloat> = 210...360
    static let listRange: ClosedRange<CGFloat> = 260...520
    static let detailMin: CGFloat = 420

    /// The on-screen list in its sort order.
    private(set) var displayed: [SireQuestion] = []
    /// List selection (Q-3: several rows may be selected; the detail shows `primary`).
    var selection: Set<String> = [] {
        didSet { if selection != oldValue { selectionDidChange(from: oldValue) } }
    }
    /// The question shown in the detail pane (the last-clicked row).
    private(set) var primary: String?
    /// Questions whose Gemini request is running (SIRE-029 step 3).
    private(set) var aiBusy: Set<String> = []
    /// Bumped to ask the list to scroll the primary row into view.
    private(set) var scrollRequest = 0
    /// The new-task field text (SIRE-027).
    var newTaskText = ""

    let body = SireBodyController()
    @ObservationIgnored private var byNumber: [String: SireQuestion] = [:]

    init() {
        if let saved = MacPreferences.shared.codable(.sireFilters, as: SirePersistedFilters.self) {
            restoring = true
            criteria = saved.criteria
            chaptersExpanded = saved.chaptersExpanded
            vesselsExpanded = saved.vesselsExpanded
            typesExpanded = saved.typesExpanded
            filterPaneVisible = saved.filterPaneVisible
            if let w = saved.filterWidth { filterWidth = min(max(CGFloat(w), Self.filterRange.lowerBound), Self.filterRange.upperBound) }
            if let w = saved.listWidth { listWidth = min(max(CGFloat(w), Self.listRange.lowerBound), Self.listRange.upperBound) }
            restoring = false
        }
        #if DEBUG
        // Snapshot runs (ARCH §9.6) render after a fixed idle time: load the bank synchronously so the list is ready.
        if ProcessInfo.processInfo.environment["AA_SIRE_SELECT"] != nil, !SireBank.shared.isLoaded,
           let data = AAResources.data(name: "sire2_question_bank", ext: "json"),
           let contents = try? SireBankDecoder.load(data) {
            SireBank.shared.install(contents)
        }
        #endif
    }

    // MARK: Wiring

    /// Binds to the app environment once (flush hook, data-model swaps).
    func attach(_ env: AppEnvironment) {
        guard self.env !== env else { return }
        if let t = flushToken, let old = self.env { old.flush.unregister(t) }
        self.env = env
        subscriptions.removeAll()
        subscriptions.append(env.store.dataReplaced.subscribe { [weak self] _ in self?.dataReplaced() })
        flushToken = env.flush.register(container: nil, host: "sire-body") { [weak self] in self?.body.flush() }
        body.attach(env)
        _ = SireGeminiKeys.store(env)                                      // DECISIONS 12: import once
    }

    var state: SireState? { env?.store.data.sire }

    var session: SireSessionSnapshot {
        guard let s = state else { return SireSessionSnapshot() }
        return SireSessionSnapshot(s)
    }

    // MARK: Loading (SIRE-001/002)

    var bank: SireBank { SireBank.shared }

    /// First activation: loads the bank off the main actor, builds the filters and the list.
    func ensureLoaded() async {
        if browser != nil { return }
        let result = await bank.load()
        guard case .success(let contents) = result, browser == nil else { return }
        browser = SireBrowser(contents)
        byNumber = Dictionary(contents.questions.map { ($0.questionNumber, $0) }, uniquingKeysWith: { a, _ in a })
        applyFilters()
        #if DEBUG
        if let pick = ProcessInfo.processInfo.environment["AA_SIRE_SELECT"] {
            let picks = pick.split(separator: ",").map(String.init).filter { byNumber[$0] != nil }
            if let last = picks.last {
                selection = Set(picks)
                scrollRequest += 1
                if primary != last { primary = last; body.load(question: byNumber[last]) }
            }
        }
        #endif
    }

    func question(_ n: String?) -> SireQuestion? { n.flatMap { byNumber[$0] } }
    var primaryQuestion: SireQuestion? { question(primary) }

    // MARK: Filtering (§3.9)

    /// `ApplyFilters`: re-filters, keeps rows of the selection that are still visible (SIRE-015).
    func applyFilters() {
        guard let browser else { return }
        body.flush()                                            // SIRE-015: flush before the list is swapped
        let list = browser.apply(criteria, session: session)
        displayed = list
        let visible = Set(list.map(\.questionNumber))
        let kept = selection.intersection(visible)
        if kept != selection { selection = kept }
    }

    func resetFilters() {
        guard browser != nil else { return }                  // SIRE-012: nothing until loaded
        criteria = SireFilterCriteria.reset
    }

    func setAllChapters(_ on: Bool) {
        guard let b = browser else { return }
        criteria.uncheckedChapters = on ? [] : Set(b.chapterOptions.map(\.key))
    }

    func binding(chapter key: String) -> Binding<Bool> {
        Binding(get: { !self.criteria.uncheckedChapters.contains(key) },
                set: { on in if on { self.criteria.uncheckedChapters.remove(key) } else { self.criteria.uncheckedChapters.insert(key) } })
    }

    func binding(vessel key: String) -> Binding<Bool> {
        Binding(get: { !self.criteria.uncheckedVessels.contains(key) },
                set: { on in if on { self.criteria.uncheckedVessels.remove(key) } else { self.criteria.uncheckedVessels.insert(key) } })
    }

    func binding(type key: String) -> Binding<Bool> {
        Binding(get: { !self.criteria.uncheckedTypes.contains(key) },
                set: { on in if on { self.criteria.uncheckedTypes.remove(key) } else { self.criteria.uncheckedTypes.insert(key) } })
    }

    private func persistFilters() {
        guard !restoring else { return }
        var c = criteria
        c.search = ""                                          // the search box is not remembered
        MacPreferences.shared.setCodable(SirePersistedFilters(criteria: c, chaptersExpanded: chaptersExpanded,
                                                              vesselsExpanded: vesselsExpanded, typesExpanded: typesExpanded,
                                                              filterPaneVisible: filterPaneVisible)
            .withWidths(filterWidth, listWidth), .sireFilters)
    }

    func persistWidths() { persistFilters() }

    /// `Questions` before the first filter, `Questions ({n})` after (SIRE-004).
    var listHeader: String { browser == nil ? "Questions" : "Questions (\(displayed.count))" }

    /// The stats footer (SIRE-013) — derived live from the session.
    var statsText: String {
        guard let browser else { return "" }
        return browser.statsText(session: session)
    }

    // MARK: Selection (SIRE-015/016, Q-3)

    private func selectionDidChange(from old: Set<String>) {
        let added = selection.subtracting(old)
        var next = primary
        if !added.isEmpty {
            next = displayed.last { added.contains($0.questionNumber) }?.questionNumber ?? added.first
        } else if let p = primary, !selection.contains(p) {
            next = displayed.first { selection.contains($0.questionNumber) }?.questionNumber
        }
        if selection.isEmpty { next = nil }
        guard next != primary else { return }
        body.flush()                                            // persist the previous question's edits first
        primary = next
        newTaskText = ""
        body.load(question: question(next))
    }

    // MARK: Data-model swap (SIRE-040, §6.11)

    private func dataReplaced() {
        body.discardAfterSwap()
        applyFilters()                                          // Q-10 fix: re-filter on swap
        body.load(question: primaryQuestion)
    }

    // MARK: Status / bookmark / export tag (SIRE-017…019)

    func status(of n: String) -> SireQuestionStatus { state?.status(for: n) ?? .none }

    func setStatus(_ s: SireQuestionStatus) {
        guard let env, let n = primary, let state else { return }
        state.setStatus(s, for: n)
        env.store.markDirty()
        if criteria.status != .all { applyFilters() }           // only status changes re-filter (Q-7)
    }

    func toggleBookmark() {
        guard let env, let n = primary, let state else { return }
        state.toggleBookmark(n)
        env.store.markDirty()
    }

    func toggleForExport() {
        guard let env, let n = primary, let state else { return }
        state.toggleForExport(n)
        env.store.markDirty()
    }

    // MARK: Tasks (SIRE-026…028)

    var primaryTasks: [SireTask] { primary.flatMap { state?.tasks(for: $0) } ?? [] }

    var tasksHeader: String { primary == nil ? "Tasks" : "Tasks (\(primaryTasks.count))" }

    /// SIRE-027: trimmed, empty ignored, no de-duplication.
    func commitNewTask() {
        guard let env, let n = primary, let state else { return }
        let text = NetText.trim(newTaskText)
        guard !text.isEmpty else { return }
        state.tasks.append(SireTask(questionNumber: n, text: text, isCompleted: false, createdAt: env.clock.now()))
        newTaskText = ""
        env.store.markDirty()
    }

    func toggleDone(_ task: SireTask) {
        guard let env else { return }
        task.isCompleted.toggle()
        env.store.markDirty()
    }

    /// Removed immediately, no confirmation.
    func remove(_ task: SireTask) {
        guard let env, let state, let i = state.tasks.firstIndex(where: { $0 === task }) else { return }
        _ = withAnimation(.snappy) { state.tasks.remove(at: i) }
        env.store.markDirty()
    }

    /// VIEW-212 row 23 / SIRE-030: adds the picked candidates (candidate order) to `question`, skipping blanks and
    /// case-insensitive duplicates of existing tasks or of earlier picks. Returns the number added.
    @discardableResult
    func addCandidates(_ picked: [String], to question: String) -> Int {
        guard let env, let state else { return 0 }
        var existing = Set(state.tasks(for: question).map { NetText.toUpperInvariant($0.text) })
        var added = 0
        for text in picked {
            let key = NetText.toUpperInvariant(text)
            if text.isEmpty || existing.contains(key) { continue }
            state.tasks.append(SireTask(questionNumber: question, text: text, isCompleted: false, createdAt: env.clock.now()))
            existing.insert(key)
            added += 1
        }
        if added > 0 { env.store.markDirty() }
        return added
    }

    /// `📋 Identified…` (SIRE-028).
    func showIdentified(dialogs: DialogPresenter) async {
        guard let q = primaryQuestion, let browser else { return }
        let identified = browser.identified.tasks(for: q.questionNumber)
        if identified.isEmpty {
            await dialogs.info("Identified tasks", "No tasks could be identified from this question's guidance text.")
            return
        }
        await pickAndAdd(prompt: "\(identified.count) tasks identified for Q \(q.questionNumber) — tick to add:",
                         candidates: identified, question: q.questionNumber, dialogs: dialogs)
    }

    /// `✦ AI Suggest…` (SIRE-029): the originating question is captured up front (Q-4 fix).
    func aiSuggest(dialogs: DialogPresenter) async {
        guard let env, let q = primaryQuestion else { return }
        if !q.isDetailedQuestion {
            await dialogs.info("AI Suggest", "AI task suggestions only apply to detailed inspection questions.")
            return
        }
        guard let key = SireGeminiKeys.store(env).key(), !NetText.isBlank(key) else {
            await dialogs.info("AI Suggest", "No Gemini API key is set. Add yours via Tools ▸ 'Set Gemini API key…' to enable AI task suggestions.")
            return
        }
        aiBusy.insert(q.questionNumber)
        let result = await SireGeminiClient().suggestTasks(for: q, apiKey: key)
        aiBusy.remove(q.questionNumber)
        switch result {
        case .failure(let e): await dialogs.warning("AI Suggest", e.message)
        case .success(let tasks):
            await pickAndAdd(prompt: "Gemini suggested \(tasks.count) tasks for Q \(q.questionNumber) — tick to add:",
                             candidates: tasks, question: q.questionNumber, dialogs: dialogs)
        }
    }

    private func pickAndAdd(prompt: String, candidates: [String], question: String, dialogs: DialogPresenter) async {
        var picked: [String]?
        await dialogs.presentSheet(.decision) { dismiss in
            SireCandidatePickerSheet(prompt: prompt, candidates: candidates) { result in picked = result; dismiss() }
        }
        if let picked { addCandidates(picked, to: question) }
    }

    // MARK: Quick-add to AA (SIRE-031…035)

    private func pickKind(for q: SireQuestion, dialogs: DialogPresenter) async -> SireAddKind? {
        let def = SireAddKind.fromDominantCategory(SireTagExtractor.dominantCategory(q))
        var kind: SireAddKind?
        await dialogs.presentSheet(.decision) { dismiss in
            SireKindPickerSheet(defaultKind: def) { k in kind = k; dismiss() }
        }
        return kind
    }

    func addThisQuestion(dialogs: DialogPresenter) async {
        guard let env, let q = primaryQuestion, let browser else { return }
        guard let kind = await pickKind(for: q, dialogs: dialogs) else { return }
        let r = SireToAa.addQuestion(q, kind: kind, identified: browser.identified, store: env.store)
        await finishAdd(r, dialogs: dialogs)
    }

    func addWholeSection(dialogs: DialogPresenter) async {
        guard let env, let q = primaryQuestion, let contents = bank.contents else { return }
        let count = contents.inSection(q.section).count
        let ok = await dialogs.alert(AlertSpec(
            title: "Add section",
            message: "Add all \(count) question(s) in section \(q.section) to AA under one item (plus their identified tasks as top-level Tasks)?",
            style: .informational,
            buttons: [AlertButton(title: "Continue", role: .default), AlertButton(title: "Cancel", role: .cancel)])) == 0
        guard ok, let kind = await pickKind(for: q, dialogs: dialogs) else { return }
        await finishAdd(SireToAa.addSection(q.section, kind: kind, bank: contents, store: env.store), dialogs: dialogs)
    }

    func addWholeChapter(dialogs: DialogPresenter) async {
        guard let env, let q = primaryQuestion, let contents = bank.contents else { return }
        let count = contents.inChapter(q.chapter).count
        let ok = await dialogs.alert(AlertSpec(
            title: "Add chapter",
            message: "Add all \(count) question(s) in chapter \(q.chapter) to AA under one item (plus their identified tasks as top-level Tasks)?\n\nThis can create many items and tasks.",
            style: .warning,
            buttons: [AlertButton(title: "Continue", role: .default), AlertButton(title: "Cancel", role: .cancel)])) == 0
        guard ok, let kind = await pickKind(for: q, dialogs: dialogs) else { return }
        await finishAdd(SireToAa.addChapter(q.chapter, kind: kind, bank: contents, store: env.store), dialogs: dialogs)
    }

    /// `FinishAdd`: save (errors swallowed), the hierarchy lists refresh by observation, then "Go to it now?".
    private func finishAdd(_ r: SireAddResult, dialogs: DialogPresenter) async {
        guard let env else { return }
        guard let primary = r.primary else {
            await dialogs.info("Add to AA", r.summary)
            return
        }
        try? env.store.save()
        let id = primary.id
        let go = await dialogs.alert(AlertSpec(
            title: "Added to AA", message: r.summary + "\n\nGo to it now?", style: .informational,
            buttons: [AlertButton(title: "Go to Item", role: .default), AlertButton(title: "Not Now", role: .cancel)])) == 0
        if go { env.navigator.navigate(to: id) }
    }

    // MARK: Export (SIRE-036)

    /// `filtered` for `Current Filter Results`: the displayed list, or every question in bank order when the tab was
    /// never populated.
    func exportFiltered(all: [SireQuestion]) -> [SireQuestion] { browser == nil ? all : displayed }
}

/// The per-process Gemini key store (DECISIONS 12: the settings.json key is imported on first use).
@MainActor enum SireGeminiKeys {
    private static var cached: (ObjectIdentifier, GeminiKeyStore)?

    static func store(_ env: AppEnvironment) -> GeminiKeyStore {
        let id = ObjectIdentifier(env.settings)
        if let c = cached, c.0 == id { return c.1 }
        let s = GeminiKeyStore(secrets: env.settings.secrets, settings: env.settings)
        s.importFromSettingsOnce()
        cached = (id, s)
        return s
    }
}
