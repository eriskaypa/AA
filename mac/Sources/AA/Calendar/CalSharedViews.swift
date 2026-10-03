// Spec: 07 §7 (Mac adaptation: header strips, immediate saves surfaced as alerts — W-17, store resolved at action
//       time — W-01, live refresh allowed — VIEW-021, reload re-init — VIEW-207), 07 VIEW-202 / VIEW-214 (the shared
//       saved-list → tasks flow used by Board and Planner), VIEW-206 (editors opened from these pages, then flush +
//       refresh), ARCHITECTURE.md §2.4 (hold ids, re-resolve), §7.5 (presenter), §8 (design tokens), §9.7 (memoised
//       derived collections invalidated by observation).
import AppKit
import UniformTypeIdentifiers
import SwiftUI
import AACore

// MARK: Header strip

/// The bordered title strip every W-PLAN page starts with (WPF `Panel` header → Mac bar material + hairline).
struct CalPageHeader<Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    var symbol: String? = nil
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        // One row when it fits; otherwise the controls move under the title so nothing is clipped.
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: AASpacing.m) {
                titleBlock.fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: AASpacing.s)
                trailing()
            }
            VStack(alignment: .leading, spacing: AASpacing.s) {
                titleBlock
                HStack(spacing: AASpacing.m) {
                    trailing()
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.horizontal, AASpacing.l)
        .padding(.vertical, 10)
        .frame(minHeight: 52)
        .background(.bar)
        .overlay(alignment: .bottom) { Rectangle().fill(AAColor.border).frame(height: 1) }
    }

    private var titleBlock: some View {
        HStack(alignment: .center, spacing: AASpacing.m) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AAColor.tint)
                    .frame(width: 22)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.aaMono(AAType.title, weight: .bold))
                    .foregroundStyle(AAColor.accent)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.aaMono(AAType.caption))
                        .foregroundStyle(AAColor.muted)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
        }
    }
}

/// A small pane header ("Calendar", "Unscheduled Jobs", "Inspect", "Buckets").
struct CalPaneTitle<Trailing: View>: View {
    let title: String
    var symbol: String? = nil
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: AASpacing.s) {
            if let symbol {
                Image(systemName: symbol).foregroundStyle(AAColor.tint).font(.system(size: 13, weight: .semibold))
                    .accessibilityHidden(true)
            }
            Text(title).font(.aaMono(15, weight: .bold)).foregroundStyle(AAColor.accent).lineLimit(1)
            Spacer(minLength: AASpacing.xs)
            trailing()
        }
        .padding(.horizontal, AASpacing.m)
        .padding(.vertical, AASpacing.s)
    }
}

extension CalPaneTitle where Trailing == EmptyView {
    init(title: String, symbol: String? = nil) {
        self.init(title: title, symbol: symbol) { EmptyView() }
    }
}

// MARK: Resizable two-pane split (WPF GridSplitter, 6 wide; width not persisted)

/// A leading pane of adjustable width, a 6-pt splitter (1-pt hairline, resize cursor, drag to resize) and a trailing
/// pane that fills. Pure SwiftUI on purpose: an `HSplitView` (NSSplitView) ignores the main window's bottom
/// `safeAreaInset` (the shortcut strip, SHELL-024), so its panes ran underneath the strip.
struct CalSplitView<Leading: View, Trailing: View>: View {
    let minLeading: CGFloat
    let idealLeading: CGFloat
    let maxLeading: CGFloat
    var minTrailing: CGFloat = 360
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var trailing: () -> Trailing
    @State private var width: CGFloat?
    @State private var dragBase: CGFloat?
    @State private var hovering = false

    static var splitterWidth: CGFloat { 6 }

    var body: some View {
        GeometryReader { geo in
            let w = clamped(width ?? idealLeading, total: geo.size.width)
            HStack(spacing: 0) {
                leading()
                    .frame(width: w)
                    .frame(maxHeight: .infinity)
                    .clipped()
                splitter(current: w, total: geo.size.width)
                trailing()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            }
        }
    }

    private func clamped(_ v: CGFloat, total: CGFloat) -> CGFloat {
        let upper = max(minLeading, min(maxLeading, total - Self.splitterWidth - minTrailing))
        return min(max(v, minLeading), upper)
    }

    private func splitter(current: CGFloat, total: CGFloat) -> some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: Self.splitterWidth)
            .overlay {
                Rectangle()
                    .fill(hovering || dragBase != nil ? AAColor.tint.opacity(0.6) : AAColor.border)
                    .frame(width: hovering || dragBase != nil ? 2 : 1)
            }
            .contentShape(Rectangle())
            .onHover { inside in
                hovering = inside
                if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { v in
                        let base = dragBase ?? current
                        if dragBase == nil { dragBase = base }
                        width = clamped(base + v.translation.width, total: total)
                    }
                    .onEnded { _ in dragBase = nil }
            )
            .onTapGesture(count: 2) { withAnimation(.snappy) { width = idealLeading } }
            .accessibilityElement()
            .accessibilityLabel("Splitter")
            .accessibilityValue("\(Int(current)) points")
            .accessibilityAdjustableAction { dir in
                let step: CGFloat = dir == .increment ? 20 : -20
                width = clamped(current + step, total: total)
            }
    }
}

// MARK: Persistence and shared flows

@MainActor
enum CalPersist {
    /// Windows `MarkDirty(); FlushIfDirty();` / `Save()` — an immediate save whose failure is shown as an alert
    /// (W-17) instead of crashing; the store stays dirty and retries on the next save.
    static func saveNow(_ env: AppEnvironment, _ dialogs: DialogPresenter) {
        env.store.markDirty()
        flush(env, dialogs)
    }

    /// `FlushIfDirty()` with the same failure handling.
    static func flush(_ env: AppEnvironment, _ dialogs: DialogPresenter) {
        do {
            try env.store.flushIfDirty()
        } catch {
            let message = error.localizedDescription
            Task { @MainActor in await dialogs.error(ShellStatusText.saveFailedTitle, message) }
        }
    }

    /// VIEW-206 / VIEW-014: the subtask editor (any task) as a close-type sheet, then flush.
    static func editTask(_ id: UUID, env: AppEnvironment, dialogs: DialogPresenter) async {
        guard env.store.task(id: id) != nil else { return }
        await dialogs.presentSheet(.closeType) { _ in TaskItemEditorSheet(taskID: id) }
        flush(env, dialogs)
    }

    /// VIEW-206: the checklist step editor (procedure steps and crew items), then flush.
    static func editStep(_ id: UUID, env: AppEnvironment, dialogs: DialogPresenter) async {
        guard env.store.step(id: id) != nil else { return }
        await dialogs.presentSheet(.closeType) { _ in ChecklistStepEditorSheet(stepID: id) }
        flush(env, dialogs)
    }

    /// VIEW-202 / VIEW-214 (Board "+ From saved list", Planner "+ Saved list"): info when there is nothing to pick,
    /// else the shared multi-select picker; picked items become top-level tasks in selection order and are saved
    /// once. Returns how many tasks were created.
    @discardableResult
    static func addFromSavedList(env: AppEnvironment, dialogs: DialogPresenter) async -> Int {
        switch BoardSavedListAdd.candidates(env.store.data) {
        case .noLists:
            await dialogs.info(BoardSavedListAdd.title, BoardSavedListAdd.noListsMessage)
            return 0
        case .noItems:
            await dialogs.info(BoardSavedListAdd.title, BoardSavedListAdd.noItemsMessage)
            return 0
        case .rows(let rows):
            let request = ItemPickerRequest(prompt: BoardSavedListAdd.prompt,
                                            rows: rows.map { ItemPickerRow(display: $0.display, tag: $0.tag) },
                                            mode: .multi, resultOrder: .selection)
            guard let tags = await dialogs.pickItems(request), !tags.isEmpty else { return 0 }
            let created = BoardSavedListAdd.apply(tags, store: env.store)
            if !created.isEmpty { saveNow(env, dialogs) }
            return created.count
        }
    }
}

// MARK: Live derived data (ARCH §9.7)

/// Recomputes a derived value whenever anything it read changes (Observation), coalescing bursts into one rebuild
/// on the next main-actor turn. Inputs that live in the owning page model are tracked the same way.
@MainActor @Observable
final class CalLive<Value> {
    private(set) var value: Value
    @ObservationIgnored private var compute: (() -> Value)?
    @ObservationIgnored private var token = 0

    init(_ initial: Value) { value = initial }

    func bind(_ compute: @escaping () -> Value) {
        self.compute = compute
        refresh()
    }

    func refresh() {
        guard let compute else { return }
        token &+= 1
        let mine = token
        value = withObservationTracking(compute) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.token == mine else { return }
                self.refresh()
            }
        }
    }
}

// MARK: Dates

extension CivilDate {
    /// The local midnight `Date` of this civil date (for native date pickers).
    var calFoundationDate: Date {
        var c = DateComponents()
        c.year = year; c.month = month; c.day = day; c.hour = 12
        return Calendar(identifier: .gregorian).date(from: c) ?? Date()
    }

    /// The civil date of a `Date` in the current zone.
    static func calFrom(_ date: Date) -> CivilDate {
        let c = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: date)
        return CivilDate(year: c.year ?? 2000, month: c.month ?? 1, day: c.day ?? 1) ?? CivilDate(year: 2000, month: 1, day: 1)!
    }
}

/// A `#RRGGBB` token colour (Board column colours, fixed in both appearances).
func calHexColor(_ hex: String) -> Color { Color(nsColor: AAColor.hex(hex)) }

/// Board / Planner drag payloads travel in-process: the dragged ref is remembered here when the drag starts so
/// drop targets can validate and preview synchronously (the item provider still carries the JSON for completeness).
@MainActor
final class CalDragSession {
    static let shared = CalDragSession()
    var job: PlannerJobRef?
    var taskID: UUID?
}

extension NSItemProvider {
    /// An item provider carrying a Codable payload under a private type identifier.
    static func calPayload<T: Encodable>(_ value: T, type: UTType) -> NSItemProvider {
        let p = NSItemProvider()
        let data = (try? JSONEncoder().encode(value)) ?? Data()
        p.registerDataRepresentation(forTypeIdentifier: type.identifier, visibility: .ownProcess) { done in
            done(data, nil)
            return nil
        }
        return p
    }
}

/// The keyboard modifiers held right now (click handlers on app-drawn cards and chips).
@MainActor
func calCurrentModifiers() -> EventModifiers {
    let f = NSEvent.modifierFlags
    var m: EventModifiers = []
    if f.contains(.command) { m.insert(.command) }
    if f.contains(.shift) { m.insert(.shift) }
    if f.contains(.option) { m.insert(.option) }
    return m
}
