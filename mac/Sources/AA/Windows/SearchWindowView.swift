// Spec: 08 §2.4 (QUICK-120…125), §3.4 (run, BuildHighlighted), §6.2-D (Table Where / Match, highlighted run black
//       bold on #FFE066 in both appearances, search off-main over a Sendable snapshot, generation counter — Q-10 fix),
//       §6.3; 02 REPO-100…105, §6.6; DECISIONS 08 OQ-3 (one reusable window; ⌘F / ⇧⌘F open-or-focus it and select
//       the query), 02 Q-11 (a hit opens its owner with the matched child selected), OC-11 (gated items: Name and
//       Tags only); 03 SHELL-673 (↩ in the query runs, ↩ in the results navigates), §6.5.1.5; ARCHITECTURE.md §7.7.
import AppKit
import SwiftUI
import AACore

/// Edit ▸ Find ▸ Search All Items… (⌘F) — global full-text search with highlighted snippets.
struct SearchWindowView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var model = SearchWindowModel()
    @State private var selection: Int?
    @FocusState private var queryFocused: Bool
    private let bridge = SearchWindowBridge.shared

    /// Debug snapshots start with a query already run.
    var initialQuery: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            queryBar
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 10)
            results
            Divider()
            statusBar
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
        }
        .frame(minWidth: 640, idealWidth: 900, minHeight: 360, idealHeight: 640)
        .navigationTitle(SearchWindowText.windowTitle)
        .onAppear {
            focusQuery(selectAll: true)
            if let q = initialQuery, model.query.isEmpty {
                model.query = q
                model.run(env: env)
            }
        }
        .onChange(of: bridge.focusRequest) { _, _ in focusQuery(selectAll: bridge.selectAll) }
        .onChange(of: env.store.generation) { _, _ in model.invalidate() }
    }

    // MARK: Query bar (QUICK-121)

    private var queryBar: some View {
        HStack(spacing: 8) {
            Text(SearchWindowText.queryLabel)
                .frame(width: 60, alignment: .leading)
                .foregroundStyle(AAColor.fg)
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(AAColor.muted)
                TextField(SearchWindowText.queryPrompt, text: $model.query)
                    .textFieldStyle(.plain)
                    .font(.aaMono(AAType.body))
                    .focused($queryFocused)
                    .onSubmit { model.run(env: env) }
                    .aaFilterField(for: .search)
                if !model.query.isEmpty {
                    Button { model.query = ""; model.run(env: env); focusQuery(selectAll: false) } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(AAColor.muted)
                    }
                    .buttonStyle(.borderless)
                    .help("Clear")
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(AAColor.panelAlt, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(queryFocused ? AAColor.tint.opacity(0.7) : AAColor.border, lineWidth: 1))
            Button(SearchWindowText.searchButton) { model.run(env: env) }
                .aaProminent()
                .frame(minWidth: 80)
                .disabled(model.isRunning)
        }
    }

    // MARK: Results (QUICK-124, QUICK-125)

    private var results: some View {
        Table(model.hits, selection: $selection) {
            TableColumn(SearchWindowText.whereColumn) { h in
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        AAKindBadge(kind: h.ownerKind, compact: true)
                        Text(h.ownerHeader).font(.system(size: AAType.body, weight: .bold)).lineLimit(1)
                            .truncationMode(.tail)
                    }
                    Text(h.whereLabel).font(.system(size: AAType.caption)).foregroundStyle(AAColor.fg.opacity(0.7))
                        .lineLimit(1)
                }
                .padding(.vertical, 2)
                .help(h.ownerHeader)
            }
            .width(min: 180, ideal: 230)
            TableColumn(SearchWindowText.matchColumn) { h in
                Text(SearchWindowView.highlighted(h))
                    .font(.aaMono(AAType.body))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(h.snippet)
            }
            .width(min: 300, ideal: 600)
        }
        .tableStyle(.inset(alternatesRowBackgrounds: true))
        .contextMenu(forSelectionType: Int.self) { ids in
            if let id = ids.first, let h = model.hits.first(where: { $0.id == id }) {
                Button { open(h) } label: { Label("Open \(h.ownerHeader)", systemImage: "arrow.up.forward.app") }
            }
        } primaryAction: { ids in
            if let id = ids.first, let h = model.hits.first(where: { $0.id == id }) { open(h) }
        }
        .onKeyPress(.return) {
            guard let id = selection, let h = model.hits.first(where: { $0.id == id }) else { return .ignored }
            open(h)
            return .handled
        }
        .aaListCommands(ListCommands(role: .searchResults, selectionCount: selection == nil ? 0 : 1,
                                     primary: { if let id = selection, let h = model.hits.first(where: { $0.id == id }) { open(h) } }))
        .overlay {
            if model.hits.isEmpty && !model.isRunning {
                if model.lastQuery.isEmpty {
                    AAEmptyState(title: "Search every item", symbol: "magnifyingglass",
                                 message: "Names, tags, descriptions, notes, file names and paths, components, subtasks and checklist steps. Press Return to search.")
                        .allowsHitTesting(false)
                } else {
                    AAEmptyState(title: "No results", symbol: "magnifyingglass", message: model.status)
                        .allowsHitTesting(false)
                }
            }
        }
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            if model.isRunning { ProgressView().controlSize(.small) }
            Text(model.status)
                .font(.system(size: AAType.caption))
                .foregroundStyle(AAColor.muted)
                .lineLimit(1)
            Spacer()
            if model.hits.count >= SearchService.maxHits {
                AAStatusCapsule(text: "first \(SearchService.maxHits) hits", symbol: "exclamationmark.triangle.fill",
                                color: AAColor.Status.dueSoon)
            }
        }
    }

    // MARK: Helpers

    /// 08 §3.4 `BuildHighlighted`: the matched run bold, black on #FFE066 (both appearances, OC-54).
    static func highlighted(_ h: SearchHit) -> AttributedString {
        let parts = SearchHighlight.split(h.snippet, start: h.matchStart, length: h.matchLength)
        var out = AttributedString(parts.prefix)
        if !parts.match.isEmpty {
            var m = AttributedString(parts.match)
            m.backgroundColor = AAColor.Status.searchHighlight
            m.foregroundColor = .black
            m.inlinePresentationIntent = .stronglyEmphasized
            out += m
        }
        out += AttributedString(parts.suffix)
        return out
    }

    private func open(_ h: SearchHit) {
        env.navigator.navigate(to: h.ownerID, childID: h.childID)
    }

    private func focusQuery(selectAll: Bool) {
        queryFocused = true
        guard selectAll else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(30))
            if let w = SceneOpener.shared.window(for: .search), let editor = w.firstResponder as? NSTextView {
                editor.selectAll(nil)
            }
        }
    }
}

/// The search run state: query, hits, status, generation (only the latest run publishes and re-enables Search).
@MainActor @Observable
final class SearchWindowModel {
    var query = ""
    private(set) var hits: [SearchHit] = []
    private(set) var status = ""
    private(set) var isRunning = false
    private(set) var lastQuery = ""
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var task: Task<Void, Never>?

    /// QUICK-122: trim; empty → clear results and status; else snapshot (gate decided on the main actor), scan off
    /// the main actor, publish only if not superseded.
    func run(env: AppEnvironment) {
        let q = NetText.trim(query)
        generation += 1
        let gen = generation
        task?.cancel()
        guard !q.isEmpty else {
            hits = []; status = ""; isRunning = false; lastQuery = ""
            return
        }
        status = SearchWindowText.searching
        isRunning = true
        let docs = SearchService.makeDocuments(store: env.store, isGated: env.locks.isGated)
        task = Task { @MainActor [weak self] in
            let found = await Task.detached(priority: .userInitiated) {
                SearchService.search(docs, query: q, isCancelled: { Task.isCancelled })
            }.value
            guard let self, gen == self.generation, !Task.isCancelled else { return }
            self.hits = found
            self.lastQuery = q
            self.status = SearchWindowText.status(count: found.count, query: q)
            self.isRunning = false
        }
    }

    /// A reload replaced the graph: hits still name valid ids (navigation re-resolves), keep them; a running scan is
    /// superseded.
    func invalidate() {
        if isRunning {
            generation += 1
            task?.cancel()
            isRunning = false
            status = ""
        }
    }
}

/// `SearchWindowActions.focusQuery` → the open Search window (single instance).
@MainActor @Observable
final class SearchWindowBridge {
    static let shared = SearchWindowBridge()
    private(set) var focusRequest = 0
    private(set) var selectAll = true

    func request(selectAll: Bool) {
        self.selectAll = selectAll
        focusRequest &+= 1
    }
}

@MainActor enum SearchWindowActions {
    /// Router Find line B: focus the Search window's query field (and select its text).
    static func focusQuery(selectAll: Bool) {
        SearchWindowBridge.shared.request(selectAll: selectAll)
        if let w = SceneOpener.shared.window(for: .search) { w.makeKeyAndOrderFront(nil) }
    }
}
