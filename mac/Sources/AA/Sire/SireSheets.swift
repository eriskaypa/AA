// Spec: 12 SIRE-030 (candidate picker: every candidate ticked, search keeps the ticks — Q-11 fix, Select All /
//       Select None, Cancel / Add, Esc cancels, long text wraps, candidate order — VIEW-212 row 23), SIRE-034 (kind
//       picker: `Add to AA as which kind?`, radio group Procedure / Task / Equipment / Area, smart default), SIRE-036/037
//       and §6.8 (export sheet: the 16 modes with Print Checklist pre-selected, live monospaced preview, Copy / Save… /
//       Cancel, Share… and Print… extras; exact status and error texts; UTF-8 without BOM, LF; waits for a running
//       bank load), ARCHITECTURE.md §7.5 (sheet contract: content views with `.aaSheet`, dismissing themselves).
import AppKit
import SwiftUI
import UniformTypeIdentifiers
import AACore

// MARK: Candidate task picker (SIRE-030)

struct SireCandidatePickerSheet: View {
    let prompt: String
    let candidates: [String]
    let finish: ([String]?) -> Void
    @State private var ticked: Set<Int>
    @State private var query = ""
    @State private var done = false

    init(prompt: String, candidates: [String], finish: @escaping ([String]?) -> Void) {
        self.prompt = prompt
        self.candidates = candidates
        self.finish = finish
        _ticked = State(initialValue: Set(candidates.indices))
    }

    /// Rows matching the search (`Contains`, case-insensitive); ticks survive filtering.
    var visible: [Int] {
        let q = NetText.trim(query)
        guard !q.isEmpty else { return Array(candidates.indices) }
        return candidates.indices.filter { NetText.containsIgnoreCase(candidates[$0], q) }
    }

    /// The ticked candidates in candidate (display) order.
    var result: [String] { candidates.indices.filter { ticked.contains($0) }.map { candidates[$0] } }

    private func complete(_ r: [String]?) {
        guard !done else { return }
        done = true
        finish(r)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AASpacing.m) {
            Text(verbatim: prompt)
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
            AASearchField(text: $query, prompt: "Filter tasks")
            List {
                ForEach(visible, id: \.self) { i in
                    Toggle(isOn: Binding(get: { ticked.contains(i) },
                                         set: { on in if on { ticked.insert(i) } else { ticked.remove(i) } })) {
                        Text(verbatim: candidates[i])
                            .font(.aaMono(AAType.body))
                            .foregroundStyle(AAColor.fg)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.vertical, AASpacing.xs)
                    }
                    .toggleStyle(.checkbox)
                }
            }
            .listStyle(.bordered)
            .alternatingRowBackgrounds(.disabled)
            .overlay {
                if visible.isEmpty {
                    AAEmptyState(title: "No matches.", symbol: "magnifyingglass",
                                 message: "Clear or change the filter to see the other tasks.")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(AAColor.panel)
                }
            }
            HStack(spacing: AASpacing.s) {
                Text(verbatim: "\(ticked.count) of \(candidates.count) selected")
                    .font(.aaMono(AAType.caption))
                    .monospacedDigit()
                    .foregroundStyle(AAColor.muted)
                    .contentTransition(.numericText())
                Button("Select All") { withAnimation(.snappy) { ticked.formUnion(visible) } }
                Button("Select None") { withAnimation(.snappy) { ticked.subtract(visible) } }
                Spacer()
                Button("Cancel") { complete(nil) }.keyboardShortcut(.cancelAction)
                Button("Add") { complete(result) }
                    .keyboardShortcut(.defaultAction)
                    .aaProminent()
            }
            .controlSize(.regular)
        }
        .padding(AASpacing.l)
        .frame(minWidth: 520, idealWidth: 600, minHeight: 420, idealHeight: 540)
        .onDisappear { complete(nil) }
        .aaSheet(.decision)
    }
}

// MARK: Kind picker (SIRE-034)

/// What a quick-add creates children from: one question (its identified tasks) or a section / chapter (its
/// questions) — §3.7 `AttachChildTasks` vs `AddQuestionChild`.
enum SireAddScope { case question, group }

struct SireKindPickerSheet: View {
    let scope: SireAddScope
    let finish: (SireAddKind?) -> Void
    @State private var kind: SireAddKind
    @State private var done = false

    init(defaultKind: SireAddKind, scope: SireAddScope = .question, finish: @escaping (SireAddKind?) -> Void) {
        self.scope = scope
        self.finish = finish
        _kind = State(initialValue: defaultKind)
    }

    static func symbol(_ k: SireAddKind) -> String {
        switch k {
        case .procedure: return "list.bullet.clipboard"
        case .task: return "checkmark.square"
        case .equipment: return "wrench.and.screwdriver"
        }
    }

    /// One muted helper line per kind (D-SIRE-09), describing what §3.7 actually creates for this scope.
    static func detail(_ k: SireAddKind, scope: SireAddScope = .question) -> String {
        switch (scope, k) {
        case (.question, .procedure): return "Identified tasks become checklist steps."
        case (.question, .task): return "Identified tasks become subtasks."
        case (.question, .equipment): return "Identified tasks become components."
        case (.group, .procedure): return "Each question becomes a checklist step."
        case (.group, .task): return "Each question becomes a subtask."
        case (.group, .equipment): return "Each question becomes a component."
        }
    }

    private func complete(_ k: SireAddKind?) {
        guard !done else { return }
        done = true
        finish(k)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AASpacing.m) {
            Text("Add to AA as which kind?").font(.headline)
            Picker(selection: $kind) {
                ForEach(SireAddKind.allCases, id: \.self) { k in
                    HStack(alignment: .firstTextBaseline, spacing: AASpacing.s) {
                        Image(systemName: Self.symbol(k))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(AAColor.kindGlyph(Self.itemKind(k)))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(verbatim: k.pickerLabel)
                            Text(verbatim: Self.detail(k, scope: scope)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .tag(k)
                }
            } label: { EmptyView() }
            .pickerStyle(.radioGroup)
            .labelsHidden()
            Text("Each identified task is also added as its own Task, linked to the new item.")
                .font(.aaMono(AAType.caption))
                .foregroundStyle(AAColor.muted)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Cancel") { complete(nil) }.keyboardShortcut(.cancelAction)
                Button("Add") { complete(kind) }.keyboardShortcut(.defaultAction).aaProminent()
            }
        }
        .padding(AASpacing.l)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
        .onDisappear { complete(nil) }
        .aaSheet(.decision)
    }

    static func itemKind(_ k: SireAddKind) -> ItemKind {
        switch k {
        case .procedure: return .procedure
        case .task: return .task
        case .equipment: return .equipment
        }
    }
}

// MARK: Export (SIRE-036/037, §6.8)

enum SireExportOutcome { case done, cancelled, cancelledWhileLoading }

struct SireExportSheet: View {
    let finish: (SireExportOutcome) -> Void
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dialogs) private var dialogs
    @State private var mode = SireExport.defaultMode
    @State private var text = ""
    @State private var generated = Date()
    @State private var lineCount = 0
    @State private var phase: SireBank.Phase = .loading
    @State private var done = false

    static func symbol(_ mode: String) -> String {
        switch mode {
        case "All Tasks": return "checklist"
        case "Completed Tasks": return "checkmark.circle"
        case "Pending Tasks": return "circle.dashed"
        case "Questions with Tasks": return "text.badge.checkmark"
        case "Selected Questions": return "checkmark.rectangle.stack"
        case "For Export Tagged": return "tag"
        case "Bookmarked Questions": return "star"
        case "Current Filter Results": return "line.3.horizontal.decrease.circle"
        case "By Chapter": return "books.vertical"
        case "By ROVIQ Location": return "mappin.and.ellipse"
        case "By Status": return "chart.bar.doc.horizontal"
        case "By Vessel Type": return "ferry"
        case "Print Checklist": return "printer"
        case "Inspection Summary": return "doc.text.magnifyingglass"
        case "Full Session Report": return "doc.richtext"
        case "Identified Tasks": return "list.clipboard"
        default: return "doc.plaintext"
        }
    }

    private func complete(_ o: SireExportOutcome) {
        guard !done else { return }
        done = true
        finish(o)
    }

    private func rebuild() {
        let vm = SireViewModel.shared
        guard let contents = SireBank.shared.contents, phase == .loaded else { return }
        generated = Date()
        text = SireExport.build(mode: mode, all: contents.questions, session: vm.session, identified: contents.identified,
                                filtered: vm.exportFiltered(all: contents.questions), selected: vm.selection,
                                now: generated, zone: .current)
        lineCount = text.utf8.reduce(0) { $1 == 0x0A ? $0 + 1 : $0 }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: AASpacing.m) {
                BuilderSheetHeader(title: "SIRE 2.0 Export", subtitle: "Choose a SIRE export:",
                                   symbol: "square.and.arrow.up.on.square")
                if phase == .loaded {
                    Text(verbatim: lineCount == 1 ? "1 line" : "\(lineCount) lines")
                        .font(.aaMono(AAType.caption)).monospacedDigit()
                        .foregroundStyle(AAColor.muted)
                        .contentTransition(.numericText())
                }
            }
            .padding(.horizontal, AASpacing.l)
            .padding(.vertical, AASpacing.m)
            Divider()
            HStack(spacing: 0) {
                List(selection: Binding(get: { Optional(mode) }, set: { if let m = $0 { mode = m } })) {
                    ForEach(SireExport.modes, id: \.self) { m in
                        Label {
                            Text(verbatim: m).font(.aaMono(AAType.body))
                        } icon: {
                            Image(systemName: Self.symbol(m)).symbolRenderingMode(.hierarchical)
                        }
                        .padding(.vertical, AASpacing.xs / 2)
                        .tag(Optional(m))
                    }
                }
                .listStyle(.inset)
                .alternatingRowBackgrounds(.disabled)
                .frame(width: 250)
                Divider()
                Group {
                    switch phase {
                    case .loaded:
                        SireTextPreview(text: text)
                    case .failed(let message):
                        AAEmptyState(title: "SIRE export", symbol: "exclamationmark.triangle",
                                     message: "Could not load the SIRE question bank:\n\(message)")
                    default:
                        VStack(spacing: AASpacing.m) {
                            ProgressView()
                            Text("Loading SIRE 2.0 question bank…")
                                .font(.aaMono(AAType.body))
                                .foregroundStyle(AAColor.muted)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            HStack(spacing: AASpacing.s) {
                ShareLink(item: text, preview: SharePreview("SIRE export “\(mode)”")) {
                    Label("Share…", systemImage: "square.and.arrow.up")
                }
                .disabled(phase != .loaded)
                Button { printText() } label: { Label("Print…", systemImage: "printer") }
                    .disabled(phase != .loaded)
                Spacer()
                Button("Cancel") { complete(phase == .loading || phase == .notLoaded ? .cancelledWhileLoading : .cancelled) }
                    .keyboardShortcut(.cancelAction)
                Button("Copy") { copy() }
                    .disabled(phase != .loaded)
                Button("Save…") { Task { await save() } }
                    .keyboardShortcut(.defaultAction)
                    .aaProminent()
                    .disabled(phase != .loaded)
            }
            .padding(.horizontal, AASpacing.l)
            .frame(minHeight: 44)
        }
        .frame(minWidth: 860, idealWidth: 940, minHeight: 560, idealHeight: 640)
        .task {
            // §6.8 / Q-10: the phase comes from the Result this call returns (never a snapshot of the shared phase,
            // which a concurrent first loader may not have published yet when this waiter resumes).
            switch await SireBank.shared.load() {
            case .success: phase = .loaded
            case .failure(let e): phase = .failed(SireBank.shared.loadError ?? e.localizedDescription)
            }
            rebuild()
        }
        .onChange(of: SireBank.shared.phase) { _, now in
            // Belt and braces: a load published by another caller while this sheet is open also releases it.
            if phase != .loaded, now == .loaded { phase = .loaded; rebuild() }
            if case .failed(let m) = now, phase == .loading { phase = .failed(m) }
        }
        .onChange(of: mode) { _, _ in rebuild() }
        .onDisappear { complete(.cancelled) }
        .aaSheet(.decision)
    }

    /// `No` = copy to the clipboard → status `SIRE export copied to clipboard.`
    private func copy() {
        let pb = NSPasteboard.general
        pb.clearContents()
        if pb.setString(text, forType: .string) {
            env.status.post("SIRE export copied to clipboard.")
            complete(.done)
        } else {
            Task { await dialogs.alert(AlertSpec(title: "Clipboard failed", message: "The text could not be put on the clipboard.",
                                                 style: .warning, buttons: [AlertButton(title: "OK", role: .default)])) }
        }
    }

    /// `Yes` = save to a .txt file (UTF-8 without BOM, LF); no confirmation on success.
    private func save() async {
        let name = SireExport.defaultFileName(mode: mode, now: generated)
        guard let url = await dialogs.savePanel(SavePanelConfig(defaultName: name, allowedTypes: [.plainText],
                                                                allowsOtherTypes: true)) else { return }
        do {
            try AtomicWrite.write(SireExport.fileData(text), to: url)
            complete(.done)
        } catch {
            await dialogs.error("Save failed", error.localizedDescription)
        }
    }

    private func printText() {
        let tv = NSTextView(frame: NSRect(x: 0, y: 0, width: 540, height: 720))
        tv.string = text
        tv.font = NSFont.monospacedSystemFont(ofSize: 9, weight: .regular)
        tv.textColor = .black
        tv.backgroundColor = .white
        let info = NSPrintInfo.shared.copy() as? NSPrintInfo ?? NSPrintInfo()
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.isVerticallyCentered = false
        let op = NSPrintOperation(view: tv, printInfo: info)
        op.jobTitle = SireExport.defaultFileName(mode: mode, now: generated)
        op.showsPrintPanel = true
        op.showsProgressPanel = true
        op.run()
    }
}

/// Read-only, selectable monospaced preview (large exports stay fast in NSTextView).
struct SireTextPreview: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.hasHorizontalScroller = true
        if let tv = scroll.documentView as? NSTextView {
            tv.isEditable = false
            tv.isSelectable = true
            tv.isRichText = false
            tv.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
            tv.textContainerInset = NSSize(width: 10, height: 10)
            tv.isHorizontallyResizable = true
            tv.textContainer?.widthTracksTextView = false
            tv.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            tv.string = text
        }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = scroll.documentView as? NSTextView, tv.string != text else { return }
        tv.string = text
        tv.scroll(.zero)
    }
}
