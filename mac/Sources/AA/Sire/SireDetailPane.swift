// Spec: 12 SIRE-016…019 (detail disabled without a selection; status buttons with the current state shown; Bookmark
//       and EXP tag toggles), SIRE-022/024 (hint strip, ↺ Reset with its tooltip), SIRE-026…029 (tasks panel:
//       checkbox, wrapping text, ✕ shown on hover, Identified… / AI Suggest… with tooltips, `✦ Asking Gemini…` while
//       busy, add field + Add), SIRE-031…033 (quick-add strip and tooltips), §6.2 (SF Symbols for the WPF glyphs,
//       empty states, `.snappy` badge animation), §6.4 rule 10 (read-only banner + actions), ARCHITECTURE.md §8.
import AppKit
import SwiftUI
import AACore

struct SireDetailPane: View {
    @Bindable var vm: SireViewModel
    @Environment(\.dialogs) private var dialogs

    var body: some View {
        Group {
            if let q = vm.primaryQuestion {
                VStack(spacing: 8) {
                    SireStatusCard(vm: vm, question: q)
                    SireQuickAddCard(vm: vm)
                    SireTasksCard(vm: vm)
                    SireBodyCard(controller: vm.body)
                }
                .padding(8)
            } else {
                AAEmptyState(title: "Select a question", symbol: "doc.text.magnifyingglass",
                             message: vm.selection.count > 1 ? "\(vm.selection.count) questions selected." : nil)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AAColor.bg, ignoresSafeAreaEdges: .top)
    }
}

/// A rounded panel card (WPF Border Panel / BorderB / radius 4).
struct SireCard<Content: View>: View {
    var alt = false
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(alt ? AnyShapeStyle(.bar) : AnyShapeStyle(AAColor.panel),
                        in: RoundedRectangle(cornerRadius: AARadius.tile, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: AARadius.tile, style: .continuous).strokeBorder(AAColor.border, lineWidth: 1))
    }
}

/// A wrapping row of buttons (WPF `WrapPanel`).
struct SireWrapLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        // An unspecified proposal asks for the narrowest (one item per line) size, so the wrap never forces its
        // container wider than the split pane gives it.
        let width = proposal.width ?? 0
        var x: CGFloat = 0, y: CGFloat = 0, lineH: CGFloat = 0, maxX: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width { x = 0; y += lineH + lineSpacing; lineH = 0 }
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            lineH = max(lineH, size.height)
        }
        return CGSize(width: min(maxX, width), height: y + lineH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineH: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX { x = bounds.minX; y += lineH + lineSpacing; lineH = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineH = max(lineH, size.height)
        }
    }
}

// MARK: Status, bookmark, export tag (SIRE-017…019)

struct SireStatusCard: View {
    @Bindable var vm: SireViewModel
    let question: SireQuestion

    var body: some View {
        let n = question.questionNumber
        let current = vm.status(of: n)
        let bookmarked = vm.state?.isBookmarked(n) ?? false
        let exported = vm.state?.isForExport(n) ?? false
        SireCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(verbatim: "Q \(n)").font(.aaMono(AAType.title, weight: .bold)).foregroundStyle(AAColor.accent)
                    Text(verbatim: question.shortQuestionText.isEmpty ? question.questionTypeDisplay : question.shortQuestionText)
                        .font(.aaMono(AAType.small))
                        .foregroundStyle(AAColor.muted)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 0)
                    Text(verbatim: question.chapterDisplay)
                        .font(.aaMono(AAType.caption))
                        .foregroundStyle(AAColor.muted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(question.chapterDisplay)
                }
                SireWrapLayout {
                    SireStatusButton(title: "In Progress", symbol: "hourglass", tint: AAColor.Status.dueSoon,
                                     active: current == .inProgress) { vm.setStatus(.inProgress) }
                    SireStatusButton(title: "Checked", symbol: "checkmark.circle", tint: AAColor.Status.ok,
                                     active: current == .checked) { vm.setStatus(.checked) }
                    SireStatusButton(title: "N/A", symbol: "minus.circle", tint: AAColor.Status.neutral,
                                     active: current == .notApplicable) { vm.setStatus(.notApplicable) }
                    SireStatusButton(title: "Clear", symbol: "xmark.circle", tint: AAColor.Status.neutral,
                                     active: false) { vm.setStatus(.none) }
                        .padding(.trailing, 12)
                    SireStatusButton(title: "Bookmark", symbol: bookmarked ? "star.fill" : "star",
                                     tint: AAColor.Status.sireAmber, active: bookmarked) { vm.toggleBookmark() }
                    SireStatusButton(title: "EXP tag", symbol: exported ? "tag.fill" : "tag", tint: AAColor.tint,
                                     active: exported) { vm.toggleForExport() }
                        .help("Tag this question for the “For Export Tagged” export.")
                }
                .controlSize(.regular)
            }
        }
        .animation(.snappy, value: current)
    }
}

/// One status / toggle button; the active state is drawn tinted (additive, SIRE-017…019).
struct SireStatusButton: View {
    let title: String
    let symbol: String
    let tint: Color
    let active: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) { Label(title, systemImage: symbol) }
            .buttonStyle(SireChipButtonStyle(tint: tint, active: active, hovering: hovering))
            .onHover { hovering = $0 }
            .accessibilityAddTraits(active ? .isSelected : [])
    }
}

/// App-drawn chip button: neutral outline, or a tinted fill when active.
struct SireChipButtonStyle: ButtonStyle {
    let tint: Color
    let active: Bool
    var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        return configuration.label
            .font(.system(.body, weight: active ? .semibold : .regular))
            .foregroundStyle(active ? tint : AAColor.fg)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(shape.fill(active ? tint.opacity(0.16) : (hovering ? AAColor.hover : AAColor.panelAlt)))
            .overlay(shape.strokeBorder(active ? tint.opacity(0.65) : AAColor.border, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(shape)
            .animation(.snappy(duration: 0.15), value: active)
    }
}

// MARK: Quick-add (SIRE-031…033)

struct SireQuickAddCard: View {
    @Bindable var vm: SireViewModel
    @Environment(\.dialogs) private var dialogs

    var body: some View {
        SireCard(alt: true) {
            SireWrapLayout {
                Label("Add to AA:", systemImage: "plus.rectangle.on.folder")
                    .font(.aaMono(AAType.small, weight: .bold))
                    .foregroundStyle(AAColor.accent)
                    .padding(.trailing, 2)
                    .frame(height: 22)
                Button("This question…") { Task { await vm.addThisQuestion(dialogs: dialogs) } }
                    .aaProminent()
                    .help("Create an AA Equipment / Task / Procedure from this question, plus its identified tasks as top-level Tasks.")
                Button("Whole section…") { Task { await vm.addWholeSection(dialogs: dialogs) } }
                    .help("Add every question in this section under one AA item, with each question as a child and its tasks spun off.")
                Button("Whole chapter…") { Task { await vm.addWholeChapter(dialogs: dialogs) } }
                    .help("Add every question in this chapter under one AA item (can be large).")
            }
        }
    }
}

// MARK: Tasks (SIRE-026…029)

struct SireTasksCard: View {
    @Bindable var vm: SireViewModel
    @Environment(\.dialogs) private var dialogs
    @FocusState private var fieldFocused: Bool

    var body: some View {
        let tasks = vm.primaryTasks
        let busy = vm.primary.map { vm.aiBusy.contains($0) } ?? false
        SireCard {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(verbatim: vm.tasksHeader)
                        .font(.aaMono(AAType.body, weight: .bold))
                        .foregroundStyle(AAColor.accent)
                        .contentTransition(.numericText())
                        .layoutPriority(1)
                    Spacer(minLength: 4)
                    ViewThatFits(in: .horizontal) {
                        taskButtons(compact: false, busy: busy)
                        taskButtons(compact: true, busy: busy)
                    }
                }
                .controlSize(.small)
                if tasks.isEmpty {
                    Text("No tasks yet").font(.aaMono(AAType.caption)).foregroundStyle(AAColor.muted)
                        .padding(.vertical, 2)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(tasks) { t in SireTaskRow(task: t, vm: vm) }
                        }
                    }
                    .frame(maxHeight: 210)
                    .fixedSize(horizontal: false, vertical: true)
                    .scrollBounceBehavior(.basedOnSize)
                }
                HStack(spacing: 6) {
                    TextField("Add a task and press Enter…", text: $vm.newTaskText)
                        .textFieldStyle(.roundedBorder)
                        .focused($fieldFocused)
                        .onSubmit { vm.commitNewTask(); fieldFocused = true }
                    Button("Add") { vm.commitNewTask(); fieldFocused = true }
                }
                .font(.aaMono(AAType.small))
            }
        }
        .animation(.snappy, value: tasks.count)
    }
}

extension SireTasksCard {
    /// `📋 Identified…` and `✦ AI Suggest…` (icon-only when the pane is narrow; the tooltips keep the full text).
    @ViewBuilder func taskButtons(compact: Bool, busy: Bool) -> some View {
        HStack(spacing: 6) {
            Button { Task { await vm.showIdentified(dialogs: dialogs) } } label: {
                Label("Identified…", systemImage: "list.clipboard")
                    .labelStyle(SireAdaptiveLabelStyle(compact: compact))
            }
            .help("Add offline-identified tasks (from the question guidance) to this question.")
            Button { Task { await vm.aiSuggest(dialogs: dialogs) } } label: {
                if busy {
                    HStack(spacing: 5) {
                        ProgressView().controlSize(.mini)
                        if !compact { Text("Asking Gemini…") }
                    }
                } else {
                    Label("AI Suggest…", systemImage: "sparkles")
                        .labelStyle(SireAdaptiveLabelStyle(compact: compact))
                }
            }
            .disabled(busy)
            .help("Ask Google Gemini for suggested tasks (needs a Gemini API key set in Tools).")
        }
        .fixedSize()
    }
}

/// Title + icon, or icon only when `compact`.
struct SireAdaptiveLabelStyle: LabelStyle {
    let compact: Bool
    func makeBody(configuration: Configuration) -> some View {
        if compact {
            configuration.icon
        } else {
            HStack(spacing: 4) { configuration.icon; configuration.title }
        }
    }
}

/// A task row: checkbox, wrapping text, ✕ on hover (removes immediately).
struct SireTaskRow: View {
    let task: SireTask
    let vm: SireViewModel
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Toggle(isOn: Binding(get: { task.isCompleted }, set: { _ in vm.toggleDone(task) })) { EmptyView() }
                .toggleStyle(.checkbox)
                .labelsHidden()
            Text(verbatim: task.text)
                .font(.aaMono(AAType.small))
                .foregroundStyle(AAColor.fg)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
            Button { vm.remove(task) } label: { Image(systemName: "xmark") }
                .buttonStyle(.borderless)
                .foregroundStyle(AAColor.muted)
                .frame(width: 20)
                .opacity(hovering ? 1 : 0)
                .help("Remove this task")
                .accessibilityLabel("Remove task")
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 4)
        .background(hovering ? AAColor.hover : Color.clear, in: RoundedRectangle(cornerRadius: AARadius.control))
        .onHover { hovering = $0 }
    }
}

// MARK: Body (SIRE-020…024)

struct SireBodyCard: View {
    let controller: SireBodyController

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("Editable — type to add line breaks / notes (Enter = new line). Your edits are saved.")
                    .font(.aaMono(AAType.caption))
                    .foregroundStyle(AAColor.muted)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help("Editable — type to add line breaks / notes (Enter = new line). Your edits are saved.")
                Spacer(minLength: 4)
                Button { controller.reset() } label: { Label("Reset", systemImage: "arrow.counterclockwise") }
                    .controlSize(.small)
                    .help("Discard your edits and restore the original SIRE formatting for this question.")
            }
            .padding(.horizontal, 8)
            .frame(height: 30)
            .background(.bar)
            .overlay(alignment: .bottom) { Rectangle().fill(AAColor.border).frame(height: 1) }
            if controller.mode == .withheld {
                AABanner(style: .warning,
                         text: "Your saved edits for this question could not be displayed on this Mac. They are kept unchanged.",
                         actions: [AABannerAction(title: "Reset to original") { controller.reset() }]
                            + (controller.richEngineAvailable
                               ? [AABannerAction(title: "Edit anyway (replaces saved edits)") { controller.editAnyway() }] : []))
                    .transition(.aaBanner)
            }
            SireBodyEditor(controller: controller)
                .frame(minHeight: 160)
        }
        .clipShape(RoundedRectangle(cornerRadius: AARadius.tile, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: AARadius.tile, style: .continuous).strokeBorder(AAColor.border, lineWidth: 1))
        .animation(.snappy, value: controller.mode)
    }
}
