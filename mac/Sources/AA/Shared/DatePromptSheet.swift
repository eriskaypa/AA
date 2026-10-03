// Spec: 04 HIER-132, 07 VIEW-203, 08 QUICK-230 (date prompt: title, wrapping prompt, date pre-set, Clear deadline (help
//       text), Cancel, OK default; OK without a date → info "Pick a date, or use "Clear deadline" to remove it." titled
//       "Set deadline", the sheet stays), 06 §6.2 / OC-55 / 08 OQ-5 (OptionalDatePicker: a field + an explicit clear
//       button + a "no date" state), DECISIONS Q-6 (edits produce .unspecified dates), DECISIONS "Stage V rulings"
//       (the field shows ISO yyyy-MM-dd; the graphical month view keeps Locale.current names, design rule 14);
//       ARCHITECTURE.md §7.5, §9.8.
import AppKit
import SwiftUI
import AACore

struct DatePromptSheet: View {
    let request: DatePromptRequest
    let finish: (DatePromptResult) -> Void
    @Environment(\.dialogs) private var dialogs
    @State private var value: NetDateTime?
    @State private var done = false

    init(request: DatePromptRequest, finish: @escaping (DatePromptResult) -> Void) {
        self.request = request
        self.finish = finish
        _value = State(initialValue: request.initial.map { NetDateTime.calendarDate($0.civilDate) })
    }

    private func complete(_ r: DatePromptResult) {
        guard !done else { return }
        done = true
        finish(r)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(request.title).font(.system(size: 14, weight: .bold))
            Text(request.prompt).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: AASpacing.m) {
                OptionalDatePicker(value: $value)
                Spacer(minLength: 0)
            }
            DatePicker("", selection: Binding(get: { ShellDateBridge.date(value) ?? Date() },
                                              set: { value = ShellDateBridge.netDate($0) }),
                       displayedComponents: .date)
                .datePickerStyle(.graphical)
                .labelsHidden()
                .opacity(value == nil ? 0.55 : 1)
                .frame(maxWidth: .infinity, alignment: .center)
            HStack {
                Button(request.clearTitle) { complete(.cleared) }
                    .help(request.clearHelp ?? "")
                Spacer()
                Button("Cancel") { complete(.cancelled) }.keyboardShortcut(.cancelAction)
                Button("OK") { ok() }.keyboardShortcut(.defaultAction).aaProminent()
            }
        }
        .padding(14)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
        .onDisappear { complete(.cancelled) }
        .aaSheet(.decision)
    }

    private func ok() {
        guard let v = value else {
            Task { @MainActor in await dialogs.info("Set deadline", request.emptyMessage) }
            return
        }
        complete(.ok(NetDateTime.calendarDate(v.civilDate)))
    }
}

/// NetDateTime (calendar date) ⇄ Date at local midnight.
enum ShellDateBridge {
    static func date(_ v: NetDateTime?) -> Date? {
        guard let v else { return nil }
        var c = DateComponents()
        c.year = v.year; c.month = v.month; c.day = v.day
        return Calendar(identifier: .gregorian).date(from: c)
    }

    /// `.unspecified` midnight of the picked day (DECISIONS Q-6).
    static func netDate(_ d: Date) -> NetDateTime {
        let c = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: d)
        let civil = CivilDate(year: c.year ?? 2000, month: c.month ?? 1, day: c.day ?? 1) ?? CivilDate(year: 2000, month: 1, day: 1)!
        return NetDateTime.calendarDate(civil)
    }

    static func date(_ c: CivilDate) -> Date? {
        var dc = DateComponents()
        dc.year = c.year; dc.month = c.month; dc.day = c.day
        return Calendar(identifier: .gregorian).date(from: dc)
    }
}

/// A date field with an explicit "no date" state: `—` + `Set…` when empty; field + clear button when set (OC-55).
struct OptionalDatePicker: View {
    let label: String?
    @Binding var value: NetDateTime?
    var earliest: CivilDate?
    var latest: CivilDate?
    var emptyTitle: String
    var setTitle: String

    init(_ label: String? = nil, value: Binding<NetDateTime?>, earliest: CivilDate? = nil, latest: CivilDate? = nil,
         emptyTitle: String = "—", setTitle: String = "Set…") {
        self.label = label
        _value = value
        self.earliest = earliest
        self.latest = latest
        self.emptyTitle = emptyTitle
        self.setTitle = setTitle
    }

    private var range: ClosedRange<Date> {
        let lo = earliest.flatMap { ShellDateBridge.date($0) } ?? Date.distantPast
        let hi = latest.flatMap { ShellDateBridge.date($0) } ?? Date.distantFuture
        return lo <= hi ? lo...hi : lo...lo
    }

    var body: some View {
        HStack(spacing: 6) {
            if let label { Text(label).foregroundStyle(AAColor.fg) }
            if value != nil {
                DatePicker("", selection: Binding(get: { ShellDateBridge.date(value) ?? Date() },
                                                  set: { value = ShellDateBridge.netDate($0) }),
                           in: range, displayedComponents: .date)
                    .datePickerStyle(.field)
                    .labelsHidden()
                    .aaISODatePicker()
                    .fixedSize()
                Button { withAnimation(.snappy) { value = nil } } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(AAColor.muted)
                }
                .buttonStyle(.borderless)
                .help("Clear the date")
                .accessibilityLabel("Clear the date")
            } else {
                Text(emptyTitle).foregroundStyle(AAColor.muted).frame(minWidth: 18)
                Button(setTitle) {
                    let today = Date()
                    let pick = min(max(today, range.lowerBound), range.upperBound)
                    withAnimation(.snappy) { value = ShellDateBridge.netDate(pick) }
                }
                .controlSize(.small)
            }
        }
    }
}
