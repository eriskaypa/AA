// Spec: 12 SIRE-001/002 (lazy load with a loading state; the load error stays on screen), SIRE-004 (Filters 250 |
//       Questions 360 | Detail *, draggable splitters), SIRE-005…014 (filter pane, list rows), SIRE-016 (empty detail),
//       §6.2 (HSplitView, sidebar-style filter pane with material, `.menu` pickers, DisclosureGroups, stats footer,
//       list rows with status capsule / amber star / EXP tag, empty states), §6.3 (↑/↓ in the list, ⌥⌘F focuses the
//       search field), DECISIONS 12 (EXP tag shown), ARCHITECTURE.md §7.2, §7.6, §7.7 (`SireTabView()`), §8.
import AppKit
import SwiftUI
import AACore

/// The `SIRE 2.0` section root (ARCH §7.7).
struct SireTabView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dialogs) private var dialogs
    @State private var vm = SireViewModel.shared
    @FocusState private var searchFocused: Bool

    var body: some View {
        ZStack {
            if vm.browser != nil {
                GeometryReader { geo in
                    let total = geo.size.width
                    HStack(spacing: 0) {
                        if vm.filterPaneVisible {
                            SireFilterPane(vm: vm, searchFocused: $searchFocused)
                                .frame(width: vm.filterWidth)
                            SireSplitHandle(width: $vm.filterWidth, range: SireViewModel.filterRange,
                                            maxAllowed: total - vm.listWidth - SireViewModel.detailMin) { vm.persistWidths() }
                        }
                        SireQuestionListPane(vm: vm)
                            .frame(width: vm.listWidth)
                        SireSplitHandle(width: $vm.listWidth, range: SireViewModel.listRange,
                                        maxAllowed: total - (vm.filterPaneVisible ? vm.filterWidth : 0) - SireViewModel.detailMin) {
                            vm.persistWidths()
                        }
                        SireDetailPane(vm: vm)
                            .frame(maxWidth: .infinity)
                    }
                }
                .transition(.opacity)
            } else {
                SireLoadingState(phase: vm.bank.phase)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: vm.browser != nil)
        .background(AAColor.bg, ignoresSafeAreaEdges: .top)
        .task {
            vm.attach(env)
            await vm.ensureLoaded()
        }
        .aaSectionCommands(.sire, SectionCommands(
            focusSearchField: {
                vm.filterPaneVisible = true
                searchFocused = true
            },
            searchFieldIsFocused: searchFocused))
    }
}

/// SIRE-001/002: `Loading SIRE 2.0 question bank…`, or the cached load error.
struct SireLoadingState: View {
    let phase: SireBank.Phase

    var body: some View {
        Group {
            if case .failed(let message) = phase {
                AAEmptyState(title: "SIRE 2.0", symbol: "exclamationmark.triangle",
                             message: "Could not load the SIRE question bank:\n\(message)")
            } else {
                VStack(spacing: AASpacing.m) {
                    ProgressView().controlSize(.large)
                    Text("Loading SIRE 2.0 question bank…")
                        .font(.aaMono(AAType.body))
                        .foregroundStyle(AAColor.muted)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AAColor.panel)
    }
}

/// A pane header strip (WPF `PanelAlt` border with padding 8,6).
struct SirePaneHeader<Trailing: View>: View {
    let title: String
    var size: CGFloat = AAType.body
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: AASpacing.s) {
            Text(verbatim: title)
                .font(.aaMono(size, weight: .bold))
                .foregroundStyle(AAColor.accent)
                .lineLimit(1)
                .contentTransition(.numericText())
            Spacer(minLength: 0)
            trailing()
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
        .background(.bar)
        .overlay(alignment: .bottom) { Rectangle().fill(AAColor.border).frame(height: 1) }
    }
}

extension SirePaneHeader where Trailing == EmptyView {
    init(title: String, size: CGFloat = AAType.body) {
        self.init(title: title, size: size) { EmptyView() }
    }
}

// MARK: Split handles (SIRE-004: draggable splitters)

/// A 1-pt divider with a 7-pt drag area; widths are clamped to the pane's range and to the room left for the detail.
struct SireSplitHandle: View {
    @Binding var width: CGFloat
    let range: ClosedRange<CGFloat>
    let maxAllowed: CGFloat
    let onEnd: () -> Void
    @State private var start: CGFloat?
    @State private var hovering = false

    var body: some View {
        Rectangle()
            .fill(hovering || start != nil ? AAColor.tint.opacity(0.6) : AAColor.border)
            .frame(width: 1)
            .padding(.horizontal, 3)
            .contentShape(Rectangle())
            .onHover { inside in
                hovering = inside
                if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { g in
                    let s = start ?? width
                    if start == nil { start = width }
                    let upper = max(range.lowerBound, min(range.upperBound, maxAllowed))
                    width = min(max(s + g.translation.width, range.lowerBound), upper)
                }
                .onEnded { _ in start = nil; onEnd() })
            .accessibilityElement()
            .accessibilityLabel("Pane divider")
    }
}

// MARK: Filters pane (SIRE-005…013)

struct SireFilterPane: View {
    @Bindable var vm: SireViewModel
    var searchFocused: FocusState<Bool>.Binding

    var body: some View {
        VStack(spacing: 0) {
            SirePaneHeader(title: "SIRE 2.0 Filters", size: 14) {
                Button("Reset") { withAnimation(.snappy) { vm.resetFilters() } }
                    .controlSize(.small)
                    .help("Clear the search and show every question again.")
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    AASearchField(text: $vm.criteria.search, prompt: "Search all questions…")
                        .focused(searchFocused)
                    SireLabeledPicker(label: "Sort by", selection: $vm.criteria.sort,
                                      items: SireSortMode.allCases.map { ($0, $0.rawValue) })
                    SireLabeledPicker(label: "Evidence category", selection: $vm.criteria.evidence,
                                      items: SireEvidenceFilter.items.map { ($0, $0) })
                    SireLabeledPicker(label: "Session status", selection: $vm.criteria.status,
                                      items: SireStatusFilter.allCases.map { ($0, $0.rawValue) })
                    if let b = vm.browser {
                        DisclosureGroup(isExpanded: $vm.chaptersExpanded) {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Button("All") { vm.setAllChapters(true) }
                                    Button("None") { vm.setAllChapters(false) }
                                }
                                .controlSize(.small)
                                .padding(.vertical, 3)
                                ForEach(b.chapterOptions) { o in
                                    Toggle(isOn: vm.binding(chapter: o.key)) { Text(verbatim: o.label).fixedSize(horizontal: false, vertical: true) }
                                }
                            }
                            .padding(.leading, 2)
                        } label: { SireGroupLabel(title: "Chapters") }
                        DisclosureGroup(isExpanded: $vm.vesselsExpanded) {
                            VStack(alignment: .leading, spacing: 3) {
                                ForEach(b.vesselOptions) { o in
                                    Toggle(isOn: vm.binding(vessel: o.key)) { Text(verbatim: o.label) }
                                }
                            }
                            .padding(.leading, 2)
                        } label: { SireGroupLabel(title: "Vessel types") }
                        DisclosureGroup(isExpanded: $vm.typesExpanded) {
                            VStack(alignment: .leading, spacing: 3) {
                                ForEach(b.typeOptions) { o in
                                    Toggle(isOn: vm.binding(type: o.key)) { Text(verbatim: o.label) }
                                }
                            }
                            .padding(.leading, 2)
                        } label: { SireGroupLabel(title: "Question type") }
                    }
                }
                .toggleStyle(.checkbox)
                .font(.aaMono(AAType.small))
                .padding(10)
            }
            Rectangle().fill(AAColor.border).frame(height: 1)
            Text(verbatim: vm.statsText)
                .font(.aaMono(AAType.caption))
                .foregroundStyle(AAColor.muted)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .textSelection(.enabled)
        }
        .background(AAPaneBackground().ignoresSafeArea(edges: .top))
    }
}

struct SireGroupLabel: View {
    let title: String
    var body: some View {
        Text(verbatim: title).font(.aaMono(AAType.small, weight: .semibold)).foregroundStyle(AAColor.fg)
    }
}

/// `Sort by` / `Evidence category` / `Session status`: 11-pt muted label above a `.menu` picker.
struct SireLabeledPicker<Value: Hashable>: View {
    let label: String
    @Binding var selection: Value
    let items: [(Value, String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: label).font(.aaMono(AAType.caption)).foregroundStyle(AAColor.muted)
            Picker(selection: $selection) {
                ForEach(items, id: \.0) { v, title in Text(verbatim: title).tag(v) }
            } label: { EmptyView() }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: Question list (SIRE-014/015)

struct SireQuestionListPane: View {
    @Bindable var vm: SireViewModel

    var body: some View {
        VStack(spacing: 0) {
            SirePaneHeader(title: vm.listHeader) {
                Button {
                    withAnimation(.snappy) { vm.filterPaneVisible.toggle() }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .symbolVariant(vm.filterPaneVisible ? .fill : .none)
                }
                .buttonStyle(.borderless)
                .help(vm.filterPaneVisible ? "Hide the filters" : "Show the filters")
            }
            ScrollViewReader { proxy in
                List(selection: $vm.selection) {
                    ForEach(vm.displayed) { q in
                        SireQuestionRow(question: q, vm: vm)
                            .tag(q.questionNumber)
                            .id(q.questionNumber)
                            .listRowSeparator(.visible)
                    }
                }
                .listStyle(.inset)
                .onAppear { if let p = vm.primary { proxy.scrollTo(p, anchor: .center) } }
                .onChange(of: vm.criteria.sort) { _, _ in if let p = vm.primary { proxy.scrollTo(p, anchor: .center) } }
                .onChange(of: vm.scrollRequest) { _, _ in if let p = vm.primary { proxy.scrollTo(p, anchor: .center) } }
            }
            .overlay {
                if vm.displayed.isEmpty {
                    if NetText.isBlank(vm.criteria.search) {
                        ContentUnavailableView("No questions match", systemImage: "line.3.horizontal.decrease.circle",
                                               description: Text("Change the filters, or click Reset."))
                    } else {
                        ContentUnavailableView.search(text: NetText.trim(vm.criteria.search))
                    }
                }
            }
            .aaListCommands(ListCommands(role: .other, selectionCount: vm.selection.count))
        }
        .background(AAColor.panel, ignoresSafeAreaEdges: .top)
    }
}

/// One list row: number (52 pt, bold), short text, status capsule; EXP tag and the amber star on the right.
struct SireQuestionRow: View {
    let question: SireQuestion
    let vm: SireViewModel

    var body: some View {
        let n = question.questionNumber
        let status = vm.status(of: n)
        let bookmarked = vm.state?.isBookmarked(n) ?? false
        let exported = vm.state?.isForExport(n) ?? false
        HStack(alignment: .top, spacing: 6) {
            Text(verbatim: n)
                .font(.aaMono(AAType.small, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(AAColor.accent)
                .frame(width: 52, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                if !question.shortQuestionText.isEmpty {
                    Text(verbatim: question.shortQuestionText)
                        .font(.aaMono(AAType.small))
                        .fixedSize(horizontal: false, vertical: true)
                }
                if status != .none {
                    SireStatusBadge(status: status)
                        .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .leading)))
                }
            }
            Spacer(minLength: 4)
            HStack(spacing: 4) {
                if exported {
                    Image(systemName: "tag.fill")
                        .font(.aaMono(AAType.caption))
                        .imageScale(.small)
                        .foregroundStyle(.secondary)
                        .help("Tagged for export")
                }
                if bookmarked {
                    Image(systemName: "star.fill")
                        .font(.aaMono(AAType.caption))
                        .foregroundStyle(AAColor.Status.sireAmber)
                        .help("Bookmarked")
                }
            }
        }
        .padding(.vertical, 3)
        .animation(.snappy, value: status)
        .animation(.snappy, value: bookmarked)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// `In Progress` / `Checked` / `N/A` capsule (10 pt, SF Symbol).
struct SireStatusBadge: View {
    let status: SireQuestionStatus

    var body: some View {
        AAStatusCapsule(text: SireExport.statusDisplay(status), symbol: Self.symbol(status), color: Self.color(status))
            .fixedSize()
    }

    static func symbol(_ s: SireQuestionStatus) -> String {
        switch s {
        case .inProgress: return "hourglass"
        case .checked: return "checkmark.circle.fill"
        case .notApplicable: return "minus.circle"
        case .none: return "circle"
        }
    }

    static func color(_ s: SireQuestionStatus) -> Color {
        switch s {
        case .inProgress: return AAColor.Status.dueSoon
        case .checked: return AAColor.Status.ok
        case .notApplicable, .none: return AAColor.Status.neutral
        }
    }
}
