// Spec: 07 §3.3 VIEW-080…109 (Planner: header, navigation, range label, Unscheduled Jobs pool with search and
//       "+ Saved list", deadline-aware placement, Day/Week hour grid with 15-min snap, overlap columns and the all-day
//       "due" strip, Month grid, chips, tooltips, drops, double-click editors, save after every mutation, refresh
//       triggers, dark mode), §7.3 (Mac structure: aligned header/strip/body — W-05, visible placeholder — W-06, today
//       tint in both appearances — W-07, live drop ghost at the snapped time), DECISIONS 07 Q-06 (grey every completed
//       item), Q-07 (double-click on a procedure navigates), Q-09 (locale weekday names), 03 SHELL-632…634 (⌘← ⇧⌘T ⌘→
//       through SectionCommands), ARCHITECTURE.md §9.4 (internal drag type `com.eriskay.aa.job-ref`).
import AppKit
import SwiftUI
import UniformTypeIdentifiers
import AACore

/// The live drop preview (where the block's top will land).
struct PlannerGhost: Equatable {
    var day: CivilDate
    var minutes: Int
    var duration: Int
    var title: String
}

@MainActor @Observable
final class PlannerPageModel {
    var mode: PlannerMode = .day
    var anchor: CivilDate = CivilDate(year: 2026, month: 1, day: 1)!
    var query = ""
    var ghost: PlannerGhost?
    var targetedCell: CivilDate?
    var poolTargeted = false
    let placed = CalLive<[any SchedulableJob]>([])
    let pool = CalLive<[PlannerPoolRow]>([])
    /// Bumped whenever the grid is rebuilt for another range (scroll back to 07:00, and to today's Week column).
    var rebuildToken = 0
    /// The all-day strip shows up to `allDayExpandedMaxHeight` after "+N more" (VIEW-089, Mac addition); reset when
    /// the range changes.
    var dueExpanded = false
    @ObservationIgnored private(set) weak var store: AppStore?
    @ObservationIgnored private var loadedGeneration = -1

    func attach(_ store: AppStore) {
        if self.store === store && loadedGeneration == store.generation {
            placed.refresh(); pool.refresh()
            return
        }
        self.store = store
        loadedGeneration = store.generation
        // VIEW-080: the mode is not persisted — every Init starts in Day, anchored on today.
        mode = .day
        anchor = store.clock.today()
        #if DEBUG
        if let m = ProcessInfo.processInfo.environment["AA_WPLAN_PLANNER_MODE"], let pm = PlannerMode(rawValue: m) {
            mode = pm
        }
        #endif
        placed.bind { [weak self] in
            guard let store = self?.store else { return [] }
            return PlannerPlacement.placed(store.data)
        }
        pool.bind { [weak self] in
            guard let self, let store = self.store else { return [] }
            return PlannerPlacement.pool(store: store, query: self.query)
        }
        rebuildToken &+= 1
    }

    var today: CivilDate { store?.clock.today() ?? anchor }

    func setMode(_ m: PlannerMode) {
        guard m != mode else { return }
        mode = m
        rebuilt()
    }

    /// VIEW-081.
    func previous() { anchor = PlannerGeometry.step(anchor, mode: mode, forward: false); rebuilt() }
    func next() { anchor = PlannerGeometry.step(anchor, mode: mode, forward: true); rebuilt() }
    func goToToday() { anchor = today; rebuilt() }

    private func rebuilt() {
        dueExpanded = false
        rebuildToken &+= 1
    }

    var days: [CivilDate] { PlannerGeometry.days(mode: mode, anchor: anchor) }

    func refresh() { placed.refresh(); pool.refresh() }
}

struct PlannerTabView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dialogs) private var dialogs
    @State private var model = PlannerPageModel()
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            CalPageHeader(title: "Planner",
                          subtitle: PlannerGeometry.rangeLabel(mode: model.mode, anchor: model.anchor),
                          symbol: "calendar.day.timeline.left") {
                navigation
            }
            CalSplitView(minLeading: 200, idealLeading: 256, maxLeading: 400, minTrailing: 420) {
                PlannerPoolPane(model: model, actions: actions, searchFocused: $searchFocused)
            } trailing: {
                Group {
                    if model.mode == .month {
                        PlannerMonthGrid(model: model, actions: actions)
                    } else {
                        PlannerTimeGrid(model: model, actions: actions)
                    }
                }
            }
        }
        .background(AAColor.bg)
        .onAppear { model.attach(env.store) }
        .onChange(of: env.store.generation) { _, _ in model.attach(env.store) }
        .aaSectionCommands(.planner, SectionCommands(plannerPrevious: { model.previous() },
                                                     plannerToday: { model.goToToday() },
                                                     plannerNext: { model.next() },
                                                     focusSearchField: { searchFocused = true },
                                                     searchFieldIsFocused: searchFocused))
    }

    private var actions: PlannerActions { PlannerActions(env: env, dialogs: dialogs, model: model) }

    private var navigation: some View {
        HStack(spacing: AASpacing.m) {
            ControlGroup {
                Button { model.previous() } label: { Label("Previous", systemImage: "chevron.left") }
                    .help("Previous (\u{2318}\u{2190})")
                Button("Today") { model.goToToday() }
                    .help("Go to today (\u{21E7}\u{2318}T)")
                Button { model.next() } label: { Label("Next", systemImage: "chevron.right") }
                    .help("Next (\u{2318}\u{2192})")
            }
            .fixedSize()
            Picker("Mode", selection: Binding(get: { model.mode }, set: { model.setMode($0) })) {
                ForEach(PlannerMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
        }
    }
}

// MARK: Actions (store resolved at action time; every mutation saves — VIEW-106)

@MainActor
struct PlannerActions {
    let env: AppEnvironment
    let dialogs: DialogPresenter
    let model: PlannerPageModel

    private func resolve(_ ref: PlannerJobRef) -> (any SchedulableJob)? { PlannerPlacement.resolve(ref, store: env.store) }

    private func saved() {
        CalPersist.saveNow(env, dialogs)
        withAnimation(.snappy) { model.refresh() }
    }

    func dropOnHour(_ ref: PlannerJobRef, day: CivilDate, minutes: Int) {
        guard let job = resolve(ref) else { return }
        PlannerPlacement.dropOnHourGrid(job, day: day, minutes: minutes)
        saved()
    }

    func dropOnMonth(_ ref: PlannerJobRef, cell: CivilDate) {
        guard let job = resolve(ref) else { return }
        PlannerPlacement.dropOnMonthCell(job, cell: cell, anchor: ref.anchor)
        saved()
    }

    func dropOnPool(_ ref: PlannerJobRef) {
        guard let job = resolve(ref) else { return }
        PlannerPlacement.dropOnPool(job)
        saved()
    }

    /// VIEW-104 + DECISIONS 07 Q-07.
    func edit(_ ref: PlannerJobRef) {
        guard let job = resolve(ref) else { return }
        switch PlannerPlacement.editorTarget(job) {
        case .navigate(let id):
            CalPersist.flush(env, dialogs)
            env.navigator.navigate(to: id)
        case .task(let id):
            Task { @MainActor in
                await CalPersist.editTask(id, env: env, dialogs: dialogs)
                model.refresh()
            }
        case .step(let id):
            Task { @MainActor in
                await CalPersist.editStep(id, env: env, dialogs: dialogs)
                model.refresh()
            }
        }
    }

    /// VIEW-105.
    func addFromSavedList() {
        Task { @MainActor in
            if await CalPersist.addFromSavedList(env: env, dialogs: dialogs) > 0 { model.refresh() }
        }
    }

    func duration(of ref: PlannerJobRef) -> (Int, String) {
        guard let j = resolve(ref) else { return (60, "") }
        return (j.durationMinutes, j.jobName)
    }
}

// MARK: Drag sources

private extension View {
    /// Every block, chip and pool row is a drag source (VIEW-103).
    func plannerDraggable(_ ref: PlannerJobRef, preview text: String) -> some View {
        onDrag {
            CalDragSession.shared.job = ref
            return NSItemProvider.calPayload(ref, type: .aaJobRef)
        } preview: {
            Text(text)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(AAColor.Status.plannerBlock, in: RoundedRectangle(cornerRadius: 4))
        }
    }
}

@MainActor
private func plannerDroppedRef(_ info: DropInfo, apply: @escaping @MainActor (PlannerJobRef) -> Void) -> Bool {
    if let ref = CalDragSession.shared.job {
        CalDragSession.shared.job = nil
        apply(ref)
        return true
    }
    guard let provider = info.itemProviders(for: [UTType.aaJobRef]).first else { return false }
    provider.loadDataRepresentation(forTypeIdentifier: UTType.aaJobRef.identifier) { data, _ in
        guard let data, let ref = try? JSONDecoder().decode(PlannerJobRef.self, from: data) else { return }
        Task { @MainActor in apply(ref) }
    }
    return true
}

// MARK: Pool (VIEW-083, VIEW-084, VIEW-102)

private struct PlannerPoolPane: View {
    @Bindable var model: PlannerPageModel
    let actions: PlannerActions
    var searchFocused: FocusState<Bool>.Binding

    var body: some View {
        let rows = model.pool.value
        VStack(alignment: .leading, spacing: 0) {
            CalPaneTitle(title: PlannerPlacement.poolTitle, symbol: "tray")
            AASearchField(text: $model.query, prompt: PlannerPlacement.poolSearchPrompt)
                .help(PlannerPlacement.poolSearchHelp)
                .focused(searchFocused)
                .padding(.horizontal, AASpacing.s)
            Button {
                actions.addFromSavedList()
            } label: {
                Label(PlannerPlacement.savedListButton, systemImage: "list.bullet.rectangle")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.small)
            .help(PlannerPlacement.savedListHelp)
            .padding(.horizontal, AASpacing.s)
            .padding(.vertical, AASpacing.s)
            List {
                ForEach(rows) { row in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(row.isDone ? AAColor.Status.plannerMuted : AAColor.Status.plannerBlock)
                            .frame(width: 4, height: 16)
                            .alignmentGuide(.firstTextBaseline) { d in d[.bottom] - 3 }
                        // VIEW-084 text "{JobName}   ·   {dur}": a long name wraps to two lines before it
                        // truncates; the duration stays readable on the first line.
                        HStack(alignment: .firstTextBaseline, spacing: 0) {
                            Text(row.job.jobName)
                                .lineLimit(2)
                                .truncationMode(.tail)
                                .fixedSize(horizontal: false, vertical: true)
                                .strikethrough(row.isDone)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(String(row.text.dropFirst(row.job.jobName.count)))
                                .lineLimit(1)
                                .fixedSize()
                                .monospacedDigit()
                                .foregroundStyle(AAColor.muted)
                        }
                        .font(.aaMono(AAType.small))
                        .foregroundStyle(row.isDone ? AAColor.muted : AAColor.fg)
                    }
                    .padding(.vertical, 2)
                    .contentShape(Rectangle())
                    .help(row.text)
                    .onTapGesture(count: 2) { actions.edit(row.ref) }
                    .plannerDraggable(row.ref, preview: row.job.jobName)
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
            .overlay {
                if rows.isEmpty {
                    Text(model.query.isEmpty ? "Every job is scheduled." : "No matching jobs.")
                        .font(.aaMono(AAType.caption)).foregroundStyle(AAColor.muted)
                        .allowsHitTesting(false)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(AAColor.tint, lineWidth: 2)
                    .background(AAColor.tint.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                    .padding(4)
                    .opacity(model.poolTargeted ? 1 : 0)
                    .allowsHitTesting(false)
            }
            .onDrop(of: [UTType.aaJobRef], delegate: PlannerPoolDropDelegate(model: model, actions: actions))
            AAHelpText(PlannerPlacement.poolHint)
                .padding(AASpacing.m)
        }
        .background(AAPaneBackground())
    }
}

private struct PlannerPoolDropDelegate: DropDelegate {
    let model: PlannerPageModel
    let actions: PlannerActions

    func validateDrop(info: DropInfo) -> Bool { info.hasItemsConforming(to: [UTType.aaJobRef]) }
    func dropEntered(info: DropInfo) { MainActor.assumeIsolated { model.poolTargeted = true } }
    func dropExited(info: DropInfo) { MainActor.assumeIsolated { model.poolTargeted = false } }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
    func performDrop(info: DropInfo) -> Bool {
        MainActor.assumeIsolated {
            model.poolTargeted = false
            return plannerDroppedRef(info) { actions.dropOnPool($0) }
        }
    }
}

// MARK: Day / Week grid (VIEW-087…096, VIEW-100)

private struct PlannerTimeGrid: View {
    @Bindable var model: PlannerPageModel
    let actions: PlannerActions
    @State private var position = ScrollPosition(edge: .top)
    @State private var hPosition = ScrollPosition(edge: .leading)

    var body: some View {
        GeometryReader { geo in
            let days = model.days
            let dayWidth = Self.dayWidth(mode: model.mode, available: geo.size.width, count: days.count)
            let total = PlannerGeometry.gutterWidth + dayWidth * Double(days.count)
            ScrollView(.horizontal) {
                // One vertical scroll view whose pinned section header holds the day names and the due strip: the
                // header, strip and hour body share one content width, so the day columns stay aligned in every
                // scroller style (W-05 / VIEW-094), and the header stays visible while the hours scroll.
                ScrollView(.vertical) {
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                        Section {
                            HStack(alignment: .top, spacing: 0) {
                                PlannerHourGutter()
                                ForEach(days, id: \.self) { day in
                                    PlannerDayCanvas(model: model, day: day, dayWidth: dayWidth, actions: actions)
                                }
                            }
                            .frame(width: total, height: PlannerGeometry.gridHeight + 8, alignment: .topLeading)
                        } header: {
                            VStack(spacing: 0) {
                                PlannerDayHeaderRow(model: model, days: days, dayWidth: dayWidth)
                                    .fixedSize(horizontal: false, vertical: true)
                                PlannerDueStrip(model: model, days: days, dayWidth: dayWidth, actions: actions)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(width: total, alignment: .leading)
                            .background(AAColor.panelAlt)
                        }
                    }
                }
                .scrollPosition($position)
                .task(id: model.rebuildToken) {
                    // VIEW-094: once the hour body has laid out, bring 07:00 to the top (just under the pinned header;
                    // 12 pt above the line so its straddling label stays readable).
                    let y = PlannerGeometry.initialScrollY - 12
                    for delay in [0, 120, 300] {
                        try? await Task.sleep(for: .milliseconds(delay))
                        if Task.isCancelled { return }
                        position.scrollTo(y: y)
                    }
                }
                .frame(width: total, height: geo.size.height)
            }
            .scrollIndicators(.automatic)
            .scrollPosition($hPosition)
            .task(id: model.rebuildToken) {
                // A week still wider than a narrow pane (columns at their 96-pt minimum): bring today's column into
                // view (centred) after every rebuild, the way the hours scroll to 07:00.
                for delay in [0, 120, 300] {
                    try? await Task.sleep(for: .milliseconds(delay))
                    if Task.isCancelled { return }
                    let x = PlannerGeometry.initialScrollX(mode: model.mode, days: model.days, today: model.today,
                                                           dayWidth: Self.dayWidth(mode: model.mode,
                                                                                   available: geo.size.width,
                                                                                   count: model.days.count),
                                                           viewport: geo.size.width)
                    hPosition.scrollTo(x: x)
                }
            }
        }
        .background(AAColor.bg)
    }

    /// VIEW-087 700 / 132, fitted to the pane (`PlannerGeometry.fittedDayWidth`: Day ≥ 700; Week shrinks to fit down
    /// to 96 so the whole week shows; the block math uses the actual width).
    static func dayWidth(mode: PlannerMode, available: Double, count: Int) -> Double {
        PlannerGeometry.fittedDayWidth(mode: mode, available: available, count: count)
    }
}

private struct PlannerDayHeaderRow: View {
    let model: PlannerPageModel
    let days: [CivilDate]
    let dayWidth: Double

    var body: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: PlannerGeometry.gutterWidth)
            ForEach(days, id: \.self) { day in
                let isToday = day == model.today
                Text(PlannerGeometry.dayHeader(mode: model.mode, day: day))
                    .font(.aaMono(AAType.small, weight: isToday ? .bold : .regular))
                    .foregroundStyle(isToday ? AAColor.tint : AAColor.fg)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 2)
                    .padding(.vertical, 6)
                    .frame(width: dayWidth)
                    .background(isToday ? AAColor.tint.opacity(0.08) : .clear)
                    .overlay(alignment: .trailing) { Rectangle().fill(AAColor.Status.plannerGrid).frame(width: 1) }
            }
        }
        .background(AAColor.panelAlt)
        .overlay(alignment: .bottom) { Rectangle().fill(AAColor.border).frame(height: 1) }
    }
}

/// VIEW-089 / 090: the all-day "due" strip. Each day's stack scrolls inside the 108-pt cap; a day whose chips do not
/// all fit shows a "+N more" row (counted from the chips' measured frames) that expands the strip, and "Show less"
/// collapses it again (Mac addition: overlay scrollers alone gave no cue that chips were hidden).
private struct PlannerDueStrip: View {
    @Bindable var model: PlannerPageModel
    let days: [CivilDate]
    let dayWidth: Double
    let actions: PlannerActions

    var body: some View {
        let placed = model.placed.value
        let perDay = days.map { PlannerPlacement.allDayChips(placed, day: $0) }
        let height = PlannerGeometry.allDayStripHeight(perDay.map { $0.map(\.text) }, dayWidth: dayWidth,
                                                       expanded: model.dueExpanded)
        HStack(alignment: .top, spacing: 0) {
            Text(PlannerPlacement.dueGutterLabel)
                .font(.aaMono(10))
                .foregroundStyle(AAColor.muted)
                .frame(width: PlannerGeometry.gutterWidth - 6, alignment: .trailing)
                .padding(.top, 5)
                .padding(.trailing, 6)
            ForEach(Array(days.enumerated()), id: \.element) { i, day in
                PlannerDueDayCell(model: model, chips: perDay[i], height: height, actions: actions)
                    .frame(width: dayWidth, height: height)
                    .background(day == model.today ? AAColor.tint.opacity(0.06) : .clear)
                    .overlay(alignment: .trailing) { Rectangle().fill(AAColor.Status.plannerGrid).frame(width: 1) }
            }
        }
        .background(AAColor.panelAlt)
        .overlay(alignment: .bottom) { Rectangle().fill(AAColor.Status.plannerGrid).frame(height: 1) }
    }
}

/// One day of the due strip: the scrolling chip stack and, when needed, the "+N more" / "Show less" row.
private struct PlannerDueDayCell: View {
    @Bindable var model: PlannerPageModel
    let chips: [PlannerChip]
    let height: Double
    let actions: PlannerActions
    /// Each chip's frame in the scroll view's visible coordinate space, and that view's visible height.
    @State private var frames: [String: CGRect] = [:]
    @State private var visibleHeight: Double = 0

    var body: some View {
        let label = PlannerGeometry.allDayMoreLabel(hidden: hiddenCount, expanded: model.dueExpanded)
        VStack(spacing: 0) {
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(chips) { chip in
                        PlannerChipView(chip: chip, wraps: true, actions: actions)
                            .onGeometryChange(for: CGRect.self) { $0.frame(in: .scrollView) } action: { r in
                                frames[chip.id] = r
                            }
                    }
                }
                .padding(3)
            }
            .onScrollGeometryChange(for: Double.self) { Double($0.containerSize.height) } action: { _, h in
                visibleHeight = h
            }
            // The "+N more" row is the cue; a legacy scroller would also narrow only the overflowing days' chips.
            .scrollIndicators(.never)
            .frame(height: max(0, height - (label == nil ? 0 : PlannerGeometry.allDayMoreRowHeight)))
            if let label {
                Button {
                    withAnimation(.snappy) { model.dueExpanded.toggle() }
                } label: {
                    Text(label)
                        .font(.aaMono(AAType.caption).monospacedDigit())
                        .foregroundStyle(AAColor.tint)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 6)
                        .frame(height: PlannerGeometry.allDayMoreRowHeight)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(model.dueExpanded ? "Show the due strip at its normal height" : "Show more of the due strip")
                .accessibilityLabel(label)
            }
        }
        .frame(height: height, alignment: .top)
        .clipped()
    }

    /// Chips cut by either edge of the visible stack (measured; frames of chips no longer in the stack are ignored).
    private var hiddenCount: Int {
        guard visibleHeight > 0 else { return 0 }
        let measured = chips.compactMap { c in frames[c.id].map { (minY: Double($0.minY), maxY: Double($0.maxY)) } }
        return PlannerGeometry.hiddenChipCount(measured, visibleHeight: visibleHeight)
    }
}

/// VIEW-092: "00:00" … "24:00" (label top = h × 46 − 7; the first one is kept inside the grid).
private struct PlannerHourGutter: View {
    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<24, id: \.self) { h in
                Color.clear
                    .frame(width: PlannerGeometry.gutterWidth, height: PlannerGeometry.hourHeight)
                    .overlay(alignment: .topLeading) { label(h).offset(y: h == 0 ? 0 : -7) }
            }
            Color.clear
                .frame(width: PlannerGeometry.gutterWidth, height: 8)
                .overlay(alignment: .topLeading) { label(24).offset(y: -7) }
        }
    }

    private func label(_ h: Int) -> some View {
        Text(PlannerGeometry.hourLabels[h])
            .font(.aaMono(11))
            .foregroundStyle(AAColor.muted)
            .fixedSize()
            .padding(.leading, 10)
    }
}

/// VIEW-093 / 095 / 096 / 100: one day column.
private struct PlannerDayCanvas: View {
    @Bindable var model: PlannerPageModel
    let day: CivilDate
    let dayWidth: Double
    let actions: PlannerActions

    var body: some View {
        let isToday = day == model.today
        let blocks = PlannerPlacement.blocks(model.placed.value, day: day, dayWidth: dayWidth)
        ZStack(alignment: .topLeading) {
            Rectangle().fill(isToday ? AAColor.tint.opacity(0.05) : Color.clear)
            Canvas { ctx, size in
                for h in 0...24 {
                    let y = PlannerGeometry.y(minutes: h * 60) + 0.5
                    var p = Path(); p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: size.width, y: y))
                    ctx.stroke(p, with: .color(AAColor.Status.plannerGrid), lineWidth: 1)
                }
                var v = Path(); v.move(to: CGPoint(x: size.width - 0.5, y: 0))
                v.addLine(to: CGPoint(x: size.width - 0.5, y: size.height))
                ctx.stroke(v, with: .color(AAColor.Status.plannerGrid), lineWidth: 1)
            }
            .allowsHitTesting(false)
            ForEach(blocks) { b in
                PlannerBlockView(block: b, actions: actions)
                    .frame(width: b.slot.width, height: b.slot.height)
                    .offset(x: b.slot.left, y: b.slot.top)
            }
            if let g = model.ghost, g.day == day {
                PlannerGhostView(ghost: g)
                    .frame(width: dayWidth - 4, height: PlannerGeometry.blockHeight(duration: g.duration))
                    .offset(x: 1, y: PlannerGeometry.y(minutes: g.minutes))
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
            if isToday {
                PlannerNowLine(width: dayWidth)
            }
        }
        .frame(width: dayWidth, height: PlannerGeometry.gridHeight, alignment: .topLeading)
        .clipped()
        .contentShape(Rectangle())
        .onDrop(of: [UTType.aaJobRef], delegate: PlannerHourDropDelegate(day: day, model: model, actions: actions))
        .frame(height: PlannerGeometry.gridHeight + 8, alignment: .top)
    }
}

/// A red "now" line in today's column (Mac addition, like Calendar.app).
private struct PlannerNowLine: View {
    let width: Double

    var body: some View {
        TimelineView(.everyMinute) { ctx in
            let c = Calendar(identifier: .gregorian).dateComponents([.hour, .minute], from: ctx.date)
            let y = PlannerGeometry.y(minutes: (c.hour ?? 0) * 60 + (c.minute ?? 0))
            ZStack(alignment: .leading) {
                Rectangle().fill(AAColor.Status.overdue).frame(width: width, height: 1.5)
                Circle().fill(AAColor.Status.overdue).frame(width: 7, height: 7).offset(x: -3)
            }
            .offset(y: y - 0.75)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct PlannerHourDropDelegate: DropDelegate {
    let day: CivilDate
    let model: PlannerPageModel
    let actions: PlannerActions

    func validateDrop(info: DropInfo) -> Bool { info.hasItemsConforming(to: [UTType.aaJobRef]) }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        MainActor.assumeIsolated {
            let minutes = PlannerGeometry.snappedMinutes(y: info.location.y)
            if let ref = CalDragSession.shared.job {
                let (dur, title) = actions.duration(of: ref)
                let g = PlannerGhost(day: day, minutes: minutes, duration: dur, title: title)
                if model.ghost != g { model.ghost = g }
            }
        }
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        MainActor.assumeIsolated { if model.ghost?.day == day { model.ghost = nil } }
    }

    func performDrop(info: DropInfo) -> Bool {
        MainActor.assumeIsolated {
            model.ghost = nil
            let minutes = PlannerGeometry.snappedMinutes(y: info.location.y)
            return plannerDroppedRef(info) { actions.dropOnHour($0, day: day, minutes: minutes) }
        }
    }
}

private struct PlannerGhostView: View {
    let ghost: PlannerGhost

    var body: some View {
        let h = ghost.minutes / 60, m = ghost.minutes % 60
        RoundedRectangle(cornerRadius: 4)
            .fill(AAColor.Status.plannerBlock.opacity(0.25))
            .overlay(RoundedRectangle(cornerRadius: 4)
                .strokeBorder(AAColor.Status.plannerBlock, style: StrokeStyle(lineWidth: 1.5, dash: [5, 3])))
            .overlay(alignment: .topLeading) {
                Text(String(format: "%02d:%02d", h, m) + "  " + ghost.title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AAColor.Status.plannerBlock)
                    .lineLimit(1)
                    .padding(.horizontal, 5).padding(.vertical, 3)
            }
    }
}

/// VIEW-095 timed block.
private struct PlannerBlockView: View {
    let block: PlannerBlock
    let actions: PlannerActions
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(block.title)
                .font(.system(size: 12, weight: .bold))
                .lineLimit(1)
                .truncationMode(.tail)
            if block.slot.showsSubtitle {
                Text(block.subtitle)
                    .font(.system(size: 10))
                    .opacity(0.9)
                    .lineLimit(1)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(block.isDone ? AAColor.Status.plannerMuted : AAColor.Status.plannerBlock,
                    in: RoundedRectangle(cornerRadius: 4, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous)
            .strokeBorder(.white.opacity(hovering ? 0.7 : 0.25), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .shadow(color: .black.opacity(hovering ? 0.25 : 0.1), radius: hovering ? 4 : 1, y: 1)
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hovering = h } }
        .help(block.tooltip)
        .onTapGesture(count: 2) { actions.edit(block.ref) }
        .plannerDraggable(block.ref, preview: block.title)
        .contextMenu { PlannerJobMenu(ref: block.ref, timed: true, actions: actions) }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Drag to move, double-click to edit")
    }
}

/// VIEW-090 / VIEW-098 chip.
private struct PlannerChipView: View {
    let chip: PlannerChip
    let wraps: Bool
    let actions: PlannerActions

    var body: some View {
        // Rule 13: the ghost opacity (0.6 / 0.55 on a span's other days) fades the fill only; the label stays at full
        // strength — white on a full chip, the foreground colour on a faded one (white would fall under 3:1).
        let fill = chip.isDone ? AAColor.Status.plannerMuted : AAColor.Status.plannerBlock
        Text(chip.text)
            .font(.aaMono(AAType.caption, weight: chip.isBold ? .bold : .regular))
            .foregroundStyle(PlannerGeometry.chipLabelIsWhite(opacity: chip.opacity) ? Color.white : AAColor.fg)
            .lineLimit(wraps ? nil : 1)
            .truncationMode(.tail)
            .fixedSize(horizontal: false, vertical: wraps)
            .padding(.horizontal, wraps ? 6 : 4)
            .padding(.vertical, wraps ? 2 : 1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fill.opacity(chip.opacity), in: RoundedRectangle(cornerRadius: 3, style: .continuous))
            .contentShape(Rectangle())
            .help(chip.tooltip)
            .onTapGesture(count: 2) { actions.edit(chip.ref) }
            .plannerDraggable(chip.ref, preview: chip.job.jobName)
            .contextMenu { PlannerJobMenu(ref: chip.ref, timed: chip.isTimed, actions: actions) }
    }
}

/// Mac addition: the same edits as the gestures, reachable from the keyboard / VoiceOver.
private struct PlannerJobMenu: View {
    let ref: PlannerJobRef
    let timed: Bool
    let actions: PlannerActions

    var body: some View {
        Button(ref.family == .procedure ? "Show in Procedures" : "Edit\u{2026}",
               systemImage: ref.family == .procedure ? "arrow.right.circle" : "pencil") { actions.edit(ref) }
        if timed {
            Button("Unschedule", systemImage: "tray.and.arrow.down") { actions.dropOnPool(ref) }
        }
    }
}

// MARK: Month (VIEW-097, VIEW-098, VIEW-101)

private struct PlannerMonthGrid: View {
    @Bindable var model: PlannerPageModel
    let actions: PlannerActions

    var body: some View {
        let cells = PlannerGeometry.monthCells(anchor: model.anchor)
        let header = PlannerGeometry.monthHeader()
        let placed = model.placed.value
        GeometryReader { geo in
            let rowHeight = max(92, (geo.size.height - 28) / 6)
            ScrollView(.vertical) {
                VStack(spacing: 0) {
                    HStack(spacing: 0) {
                        ForEach(0..<7, id: \.self) { i in
                            Text(header[i])
                                .font(.aaMono(AAType.small, weight: .bold))
                                .foregroundStyle(AAColor.fg)
                                .frame(maxWidth: .infinity)
                                .padding(4)
                        }
                    }
                    .frame(height: 28)
                    .background(AAColor.panelAlt)
                    ForEach(0..<6, id: \.self) { w in
                        HStack(spacing: 0) {
                            ForEach(0..<7, id: \.self) { d in
                                let day = cells[w * 7 + d]
                                PlannerMonthCell(model: model, day: day,
                                                 chips: PlannerPlacement.monthChips(placed, day: day), actions: actions)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: rowHeight)
                            }
                        }
                    }
                }
            }
        }
        .background(AAColor.bg)
    }
}

private struct PlannerMonthCell: View {
    @Bindable var model: PlannerPageModel
    let day: CivilDate
    let chips: [PlannerChip]
    let actions: PlannerActions

    var body: some View {
        let isToday = day == model.today
        let inMonth = day.month == model.anchor.month && day.year == model.anchor.year
        let targeted = model.targetedCell == day
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("\(day.day)")
                    .font(.aaMono(AAType.small, weight: isToday ? .bold : .regular))
                    .foregroundStyle(isToday ? Color.white : (inMonth ? AAColor.fg : AAColor.muted.opacity(0.5)))
                    .padding(.horizontal, isToday ? 5 : 0)
                    .padding(.vertical, isToday ? 1 : 0)
                    .background(isToday ? AAColor.tint : .clear, in: Capsule())
                Spacer(minLength: 0)
            }
            ScrollView(.vertical) {
                VStack(spacing: 2) {
                    ForEach(chips) { chip in PlannerChipView(chip: chip, wraps: false, actions: actions) }
                }
            }
            .scrollIndicators(.never)
        }
        .padding(3)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(targeted ? AAColor.tint.opacity(0.14) : (isToday ? AAColor.tint.opacity(0.06) : Color.clear))
        .overlay(Rectangle().strokeBorder(targeted ? AAColor.tint : AAColor.border, lineWidth: targeted ? 1.5 : 0.5))
        .contentShape(Rectangle())
        .onDrop(of: [UTType.aaJobRef], delegate: PlannerMonthDropDelegate(day: day, model: model, actions: actions))
    }
}

private struct PlannerMonthDropDelegate: DropDelegate {
    let day: CivilDate
    let model: PlannerPageModel
    let actions: PlannerActions

    func validateDrop(info: DropInfo) -> Bool { info.hasItemsConforming(to: [UTType.aaJobRef]) }
    func dropEntered(info: DropInfo) { MainActor.assumeIsolated { model.targetedCell = day } }
    func dropExited(info: DropInfo) { MainActor.assumeIsolated { if model.targetedCell == day { model.targetedCell = nil } } }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }
    func performDrop(info: DropInfo) -> Bool {
        MainActor.assumeIsolated {
            model.targetedCell = nil
            return plannerDroppedRef(info) { actions.dropOnMonth($0, cell: day) }
        }
    }
}
