// Spec: 14 TOOLS-060 (window, sections, Close = cancel), TOOLS-061 (defaults: today, Add, 0, Days, not inclusive),
//       TOOLS-062…070 (recomputed on every change; texts from ToolDateCalc), TOOLS-071 (Close / Esc, nothing
//       persisted), §6.8 (native date fields with a calendar popover, segmented operation, popup unit, free-text
//       amount with validation + stepper, copyable monospaced results); ARCHITECTURE.md §7.7 (`DateCalculatorView()`).
import AppKit
import SwiftUI
import AACore

struct DateCalculatorView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var from: Date
    @State private var to: Date
    @State private var inclusive = false
    @State private var baseDate: Date
    @State private var operation = ToolDateOperation.add
    @State private var amount = "0"
    @State private var unit = ToolDateUnit.days

    /// `today` exists for the debug snapshot registry and tests; the menu opens today's calculator (TOOLS-061).
    init(today: Date = Date(), to: Date? = nil, amount: String = "0", unit: ToolDateUnit = .days, inclusive: Bool = false) {
        _from = State(initialValue: today)
        _to = State(initialValue: to ?? today)
        _baseDate = State(initialValue: today)
        _amount = State(initialValue: amount)
        _unit = State(initialValue: unit)
        _inclusive = State(initialValue: inclusive)
    }

    private static var gregorian: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = .current
        return c
    }

    /// The civil date the picker shows (local zone, Gregorian).
    static func civil(_ d: Date) -> CivilDate? {
        let c = gregorian.dateComponents([.year, .month, .day], from: d)
        guard let y = c.year, let m = c.month, let day = c.day else { return nil }
        return CivilDate(year: y, month: m, day: day)
    }

    private var diffText: String {
        ToolDateCalc.difference(from: DateCalculatorView.civil(from), to: DateCalculatorView.civil(to), inclusive: inclusive)
    }

    private var addText: String {
        ToolDateCalc.add(date: DateCalculatorView.civil(baseDate), operation: operation, amountText: amount, unit: unit)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AASpacing.m) {
            Text("Date calculator").font(.aaMono(15, weight: .bold))
            ToolDateSection(title: "1. Difference between two dates", symbol: "arrow.left.and.right") {
                ToolDateRow(label: "From:") { picker($from) }
                ToolDateRow(label: "To:") { picker($to) }
                Toggle("Count the end date too (inclusive)", isOn: $inclusive)
                    .toggleStyle(.checkbox)
                ToolResultBox(text: diffText)
            }
            ToolDateSection(title: "2. Add / subtract from a date", symbol: "plusminus") {
                ToolDateRow(label: "Date:") { picker($baseDate) }
                HStack(spacing: AASpacing.s) {
                    Picker("Operation", selection: $operation) {
                        ForEach(ToolDateOperation.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 150)
                    HStack(spacing: 2) {
                        TextField("Amount", text: $amount)
                            .labelsHidden()
                            .multilineTextAlignment(.trailing)
                            .font(.aaMono(AAType.body))
                            .frame(width: 80)
                        Stepper("Amount", onIncrement: { step(1) }, onDecrement: { step(-1) })
                            .labelsHidden()
                    }
                    Picker("Unit", selection: $unit) {
                        ForEach(ToolDateUnit.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 110)
                    Spacer(minLength: 0)
                }
                ToolResultBox(text: addText)
            }
            Spacer(minLength: 0)
            HStack {
                Spacer()
                Button("Close") { dismiss() }
                    .frame(minWidth: 90)
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(14)
        .frame(width: 540, height: 520, alignment: .topLeading)
        .background(AAColor.bg)
    }

    private func picker(_ value: Binding<Date>) -> some View {
        ToolDateField(value: value, calendar: DateCalculatorView.gregorian)
    }

    /// Mac addition: the stepper nudges a valid amount by one (an invalid amount restarts at ±1).
    private func step(_ d: Int32) {
        let current = ToolNetNumber.parseInt32(amount) ?? 0
        let (v, overflow) = current.addingReportingOverflow(d)
        amount = String(overflow ? current : v)
    }
}

/// A date field (width 180) with a calendar popover (14 §6.8).
struct ToolDateField: View {
    @Binding var value: Date
    let calendar: Calendar
    @State private var showsCalendar = false

    var body: some View {
        HStack(spacing: AASpacing.xs) {
            DatePicker("", selection: $value, displayedComponents: .date)
                .labelsHidden()
                .datePickerStyle(.stepperField)
            Button { showsCalendar.toggle() } label: { Image(systemName: "calendar") }
                .buttonStyle(.borderless)
                .help("Show a calendar")
                .popover(isPresented: $showsCalendar, arrowEdge: .bottom) {
                    DatePicker("", selection: $value, displayedComponents: .date)
                        .labelsHidden()
                        .datePickerStyle(.graphical)
                        .environment(\.calendar, calendar)
                        .padding(AASpacing.s)
                }
        }
        .environment(\.calendar, calendar)
        .frame(width: 180, alignment: .leading)
    }
}

/// A titled panel (PanelAlt background, 1-pt border, radius 4, padding 12).
struct ToolDateSection<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: AASpacing.s) {
            Label(title, systemImage: symbol)
                .font(.aaMono(AAType.body, weight: .bold))
                .labelStyle(.titleAndIcon)
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AAColor.panelAlt, in: RoundedRectangle(cornerRadius: AARadius.control, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: AARadius.control, style: .continuous).strokeBorder(AAColor.border))
    }
}

/// `From:` / `To:` / `Date:` rows (label width 60).
struct ToolDateRow<Content: View>: View {
    let label: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(spacing: 0) {
            Text(label).frame(width: 60, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }
    }
}

/// The monospaced, wrapping, selectable result box (Panel background, border, padding 10).
struct ToolResultBox: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.aaMono(AAType.body))
            .foregroundStyle(AAColor.fg)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(AAColor.panel, in: RoundedRectangle(cornerRadius: AARadius.control, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: AARadius.control, style: .continuous).strokeBorder(AAColor.border))
            .animation(nil, value: text)
    }
}
