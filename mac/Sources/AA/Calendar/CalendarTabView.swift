// Spec: 07 §3.1 VIEW-001…022 (Calendar tab: month picker, Day/Week/Month/All Upcoming/Agenda, columns, inline Done
//       saved immediately, double-click editors / procedure navigation, batch context menu, text size A-/A+, UI-state
//       persistence, refresh triggers, dark mode), §7.1 (Mac structure), 09 CREW-091, DECISIONS 07 Q-09 / Q-12,
//       W-02 / W-03 / W-15 fixes, 03 SHELL-605/606 (⌘+ / ⌘− routed through SectionCommands), VIEW-205 (navigation
//       call site), VIEW-207 (reload re-init); ARCHITECTURE.md §7.6, §7.7.
import AppKit
import SwiftUI
import AACore

/// Page state for the Calendar (lives as long as the section root; re-initialised from `Ui` after every reload).
@MainActor @Observable
final class CalPageModel {
    var mode: CalViewMode = .day
    var selected: CivilDate = CivilDate(year: 2026, month: 1, day: 1)!
    var fontScale: Double = CalFontScale.defaultSize
    let schedule = CalLive<CalSchedule?>(nil)
    @ObservationIgnored private(set) weak var store: AppStore?
    @ObservationIgnored private var loadedGeneration = -1

    func attach(_ store: AppStore) {
        guard self.store !== store || loadedGeneration != store.generation else {
            schedule.refresh()
            return
        }
        self.store = store
        initFromUi()
        schedule.bind { [weak self] in self?.build() }
    }

    /// 07 §4.1.1 Init: `Cal.SelectedDate = Ui.CalendarSelectedDate ?? Today`; the stored mode matched exactly; a stored
    /// font size applied only within 10…30.
    private func initFromUi() {
        guard let store else { return }
        loadedGeneration = store.generation
        let ui = store.data.ui
        selected = ui.calendarSelectedDate?.civilDate ?? store.clock.today()
        mode = CalViewMode(stored: ui.calendarViewMode)
        fontScale = CalFontScale.initial(stored: ui.calendarFontScale)
    }

    private func build() -> CalSchedule? {
        guard let store else { return nil }
        if store.generation != loadedGeneration {           // VIEW-207: a reload re-inits the page from Ui
            Task { @MainActor [weak self] in self?.initFromUi() }
        }
        return CalendarRowBuilder.build(data: store.data, mode: mode, selected: selected, today: store.clock.today())
    }

    /// VIEW-003: a picked date (written to Ui like CaptureUiState would, as an Unspecified calendar date).
    func select(_ day: CivilDate) {
        guard day != selected else { return }
        selected = day
        store?.data.ui.calendarSelectedDate = NetDateTime.calendarDate(day)
    }

    /// VIEW-004: mode radios (the stored string travels as a shared preference).
    func setMode(_ m: CalViewMode) {
        mode = m
        if store?.data.ui.calendarViewMode != m.rawValue { store?.data.ui.calendarViewMode = m.rawValue }
    }

    /// VIEW-017: clamp, apply, `Ui.CalendarFontScale = size`, MarkDirty.
    func setFontScale(_ size: Double) {
        let v = CalFontScale.clamp(size)
        fontScale = v
        store?.data.ui.calendarFontScale = v
        store?.markDirty()
    }
}

struct CalendarTabView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dialogs) private var dialogs
    @State private var model = CalPageModel()
    @State private var selection = Set<String>()

    var body: some View {
        CalSplitView(minLeading: 240, idealLeading: 264, maxLeading: 420, minTrailing: 560) {
            CalSidebar(model: model)
        } trailing: {
            detail
        }
        .background(AAColor.bg)
        .onAppear { model.attach(env.store) }
        .onChange(of: env.store.generation) { _, _ in
            selection.removeAll()
            model.attach(env.store)
        }
        .aaSectionCommands(.calendar, SectionCommands(calendarFontScale: model.fontScale,
                                                      setCalendarFontScale: { model.setFontScale($0) }))
    }

    // MARK: Detail

    private var schedule: CalSchedule? { model.schedule.value }

    private var detail: some View {
        VStack(spacing: 0) {
            CalPageHeader(title: schedule?.title ?? CalendarRowBuilder.initialTitle,
                          subtitle: summary) {
                CalTextSizeControl(model: model)
                Picker("View", selection: Binding(get: { model.mode }, set: { model.setMode($0) })) {
                    ForEach(CalViewMode.allCases, id: \.self) { m in
                        Text(m.label).tag(m).help(m.help ?? "")
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .help("View")
            }
            ZStack {
                CalScheduleTable(model: model, selection: $selection, open: open)
                if let s = schedule, s.rows.isEmpty {
                    AAEmptyState(title: "Nothing scheduled", symbol: "calendar.badge.checkmark",
                                 message: "Tasks, procedures, checklist steps and crew items with a deadline in this view appear here.")
                        .allowsHitTesting(false)
                }
            }
        }
    }

    /// A short count line under the title (Mac addition; muted).
    private var summary: String {
        guard let s = schedule else { return "" }
        let n = s.rows.count
        var text = n == 1 ? "1 item" : "\(n) items"
        if let late = s.groups.first(where: { $0.role == .overdue }) { text += "  \u{00B7}  \(late.rows.count) overdue" }
        return text
    }

    // MARK: Editors (VIEW-014)

    private func open(_ rowID: String) {
        guard let row = schedule?.rows.first(where: { $0.id == rowID }) else { return }
        switch row.kind {
        case .procedure:
            env.navigator.navigate(to: row.itemID)                         // VIEW-205 (by identity, W-10)
        case .task:
            let id = row.itemID
            Task { @MainActor in
                await CalPersist.editTask(id, env: env, dialogs: dialogs)
                model.schedule.refresh()
            }
        case .step, .crewStep:
            let id = row.itemID
            Task { @MainActor in
                await CalPersist.editStep(id, env: env, dialogs: dialogs)
                model.schedule.refresh()
            }
        }
    }
}

// MARK: Sidebar (VIEW-001, VIEW-003)

private struct CalSidebar: View {
    @Environment(AppEnvironment.self) private var env
    @Bindable var model: CalPageModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CalPaneTitle(title: "Calendar", symbol: "calendar")
            DatePicker("", selection: Binding(get: { model.selected.calFoundationDate },
                                              set: { model.select(CivilDate.calFrom($0)) }),
                       displayedComponents: .date)
                .datePickerStyle(.graphical)
                .labelsHidden()
                .padding(.horizontal, AASpacing.s)
                .frame(maxWidth: .infinity)
            HStack(spacing: AASpacing.s) {
                Button {
                    model.select(env.store.clock.today())
                } label: {
                    Label("Today", systemImage: "smallcircle.filled.circle")
                }
                .controlSize(.small)
                .help("Select today")
                Spacer()
                Text(selectedText)
                    .font(.aaMono(AAType.caption))
                    .foregroundStyle(AAColor.muted)
                    .lineLimit(1)
            }
            .padding(.horizontal, AASpacing.m)
            .padding(.top, AASpacing.s)
            CalLegend()
                .padding(.horizontal, AASpacing.m)
                .padding(.top, AASpacing.l)
            Spacer(minLength: 0)
        }
        .padding(.bottom, AASpacing.m)
        .background(AAPaneBackground())
    }

    private var selectedText: String {
        CalDateText.format(model.selected, "EEE", locale: .current) + ", " + model.selected.iso
    }
}

/// What each row kind looks like (Mac addition: the kind stripe colours used in the table).
private struct CalLegend: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Shown here").font(.aaMono(AAType.caption, weight: .bold)).foregroundStyle(AAColor.muted)
            row(AAColor.kind(.task), "Tasks & subtasks")
            row(AAColor.kind(.procedure), "Procedures & steps")
            row(AAColor.crewKind, "Crew checklist items")
        }
    }

    private func row(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 10)
                .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(AAColor.border, lineWidth: 0.5))
            Text(text).font(.aaMono(AAType.caption)).foregroundStyle(AAColor.fg)
        }
    }
}

/// "Text:" A- / A+ (VIEW-017).
private struct CalTextSizeControl: View {
    @Bindable var model: CalPageModel

    var body: some View {
        HStack(spacing: 6) {
            Text("Text:").font(.aaMono(AAType.small)).foregroundStyle(AAColor.muted).fixedSize()
            ControlGroup {
                Button {
                    model.setFontScale(CalFontScale.stepped(model.fontScale, bigger: false))
                } label: {
                    Label("A-", systemImage: "textformat.size.smaller")
                }
                .help(CalFontScale.smallerHelp)
                .disabled(model.fontScale <= CalFontScale.minimum)
                Button {
                    model.setFontScale(CalFontScale.stepped(model.fontScale, bigger: true))
                } label: {
                    Label("A+", systemImage: "textformat.size.larger")
                }
                .help(CalFontScale.biggerHelp)
                .disabled(model.fontScale >= CalFontScale.maximum)
            }
            .controlGroupStyle(.navigation)
            .labelStyle(.iconOnly)
            .fixedSize()
        }
    }
}

// MARK: Schedule table (VIEW-011…016)

private struct CalScheduleTable: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dialogs) private var dialogs
    @Bindable var model: CalPageModel
    @Binding var selection: Set<String>
    let open: (String) -> Void

    private var schedule: CalSchedule? { model.schedule.value }

    var body: some View {
        let size = CGFloat(model.fontScale)
        let groups = schedule?.groups ?? []
        let grouped = schedule?.isGrouped ?? false
        Table(of: CalScheduleRow.self, selection: $selection) {
            TableColumn("Done") { row in
                CalDoneCell(row: row) { save() }
            }
            .width(min: 44, ideal: 56, max: 70)
            TableColumn("When") { row in
                Text(row.rangeDisplay)
                    .font(.aaMono(size))
                    .foregroundStyle(row.isOverdue(today: env.store.clock.today()) ? AAColor.Status.overdueMeta : AAColor.fg)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .help(CalendarRowBuilder.whenHelp)
            }
            .width(min: 120, ideal: 216, max: 300)
            TableColumn("Status") { row in
                CalStatusCell(row: row, size: size)
            }
            .width(min: 80, ideal: 112, max: 170)
            TableColumn("Task") { row in
                CalNameCell(row: row, size: size)
            }
            .width(min: 180, ideal: 340)
            TableColumn("Recurrence") { row in
                Text(row.recurrence)
                    .font(.aaMono(size))
                    .foregroundStyle(row.recurrence == "None" ? AAColor.muted : AAColor.fg)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .width(min: 70, ideal: 110, max: 140)
        } rows: {
            if grouped {
                ForEach(groups) { g in
                    Section {
                        ForEach(g.rows) { TableRow($0) }
                    } header: {
                        CalGroupHeader(group: g, size: size)
                    }
                }
            } else {
                ForEach(groups) { g in
                    ForEach(g.rows) { TableRow($0) }
                }
            }
        }
        .tableStyle(.inset(alternatesRowBackgrounds: true))
        .environment(\.defaultMinListRowHeight, max(24, size * 1.9))
        .contextMenu(forSelectionType: String.self) { ids in
            BatchContextMenuItems(selection: { objects(ids) }, refresh: { model.schedule.refresh() })
        } primaryAction: { ids in
            // Double-click / Return on a row (never a stale selection from empty space — W-15).
            if let id = ids.first, ids.count == 1 { open(id) }
        }
        .aaListCommands(ListCommands(role: .calendarTable, selectionCount: selection.count,
                                     primary: selection.count == 1 ? { if let id = selection.first { open(id) } } : nil))
    }

    /// The selected rows' underlying items in row order, repeats included (Agenda occurrences, VIEW-016 / C21).
    private func objects(_ ids: Set<String>) -> [AnyObject] {
        (schedule?.rows ?? []).filter { ids.contains($0.id) }.map(\.item)
    }

    /// VIEW-013: the model was updated first (`setComplete`), then MarkDirty + FlushIfDirty.
    private func save() { CalPersist.saveNow(env, dialogs) }
}

/// Agenda / Overdue group header: bold label (15, accent) + muted " ({count})" (VIEW-010).
private struct CalGroupHeader: View {
    let group: CalScheduleGroup
    let size: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            if group.role == .overdue {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(AAColor.Status.overdueMeta)
                    .padding(.trailing, 6)
            }
            Text(group.label ?? "")
                .font(.aaMono(15, weight: .bold))
                .foregroundStyle(group.role == .overdue ? AAColor.Status.overdueMeta : AAColor.accent)
            Text(group.countText)
                .font(.aaMono(size))
                .foregroundStyle(AAColor.muted)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
    }
}

/// Done checkbox bound to the live model (W-02 / W-03); isolated from the row's double-click (W-15).
private struct CalDoneCell: View {
    let row: CalScheduleRow
    let saved: () -> Void

    var body: some View {
        Toggle("Done", isOn: Binding(get: { row.isComplete },
                                     set: { v in if row.setComplete(v) { saved() } }))
            .toggleStyle(.checkbox)
            .labelsHidden()
            .frame(maxWidth: .infinity, alignment: .center)
            .accessibilityLabel("Done")
    }
}

private struct CalStatusCell: View {
    let row: CalScheduleRow
    let size: CGFloat

    var body: some View {
        let status = row.status
        Text(status)
            .font(.aaMono(size, weight: .semibold))
            .foregroundStyle(color(status))
            .fixedSize(horizontal: false, vertical: true)
    }

    private func color(_ s: String) -> Color {
        switch s {
        case "Done": return AAColor.Status.ok
        case "InProgress": return AAColor.tint
        case "Blocked": return AAColor.Status.overdueMeta
        default: return AAColor.fg
        }
    }
}

/// Task column: a kind stripe, the name (semi-bold, wraps, struck when complete).
private struct CalNameCell: View {
    let row: CalScheduleRow
    let size: CGFloat

    var body: some View {
        let done = row.isComplete
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(stripe)
                .frame(width: 4, height: max(12, size))
                .alignmentGuide(.firstTextBaseline) { d in d[.bottom] - 2 }
                .accessibilityHidden(true)
            Text(row.name)
                .font(.aaMono(size, weight: .semibold))
                .strikethrough(done)
                .foregroundStyle(done ? AAColor.muted : AAColor.fg)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var stripe: Color {
        switch row.kind {
        case .task: return AAColor.kind(.task)
        case .procedure, .step: return AAColor.kind(.procedure)
        case .crewStep: return AAColor.crewKind
        }
    }
}
