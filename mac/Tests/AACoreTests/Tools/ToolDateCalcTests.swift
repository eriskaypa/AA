// Tests for 14 §7.4 (date calculator, en-US and de-DE formatting), TOOLS-063…070, DECISIONS 14 Q-16.
import Foundation
import Testing
@testable import AACore

@Suite struct ToolDateCalcTests {
    let us = Locale(identifier: "en_US")
    let de = Locale(identifier: "de_DE")

    private func d(_ s: String) -> CivilDate { CivilDate(iso: s)! }

    // TV: 14 §7.4 difference table
    @Test(arguments: [
        ("2026-09-30", "2026-09-30", false, "Total: 0 days\n\u{2248} 0 weeks, 0 days\n= 0 years, 0 months, 0 days"),
        ("2026-09-30", "2026-09-30", true, "Total: 1 day (inclusive)\n\u{2248} 0 weeks, 0 days\n= 0 years, 0 months, 0 days"),
        ("2026-01-01", "2026-12-31", false, "Total: 364 days\n\u{2248} 52 weeks, 0 days\n= 0 years, 11 months, 30 days"),
        ("2026-01-01", "2026-12-31", true, "Total: 365 days (inclusive)\n\u{2248} 52 weeks, 0 days\n= 0 years, 11 months, 30 days"),
        ("2026-03-10", "2026-01-15", false, "Total: -54 days  (To is before From)\n\u{2248} 7 weeks, 5 days\n= 0 years, 1 month, 23 days"),
        ("2026-03-10", "2026-01-15", true, "Total: -55 days (inclusive)  (To is before From)\n\u{2248} 7 weeks, 5 days\n= 0 years, 1 month, 23 days"),
        ("2024-01-31", "2024-03-01", false, "Total: 30 days\n\u{2248} 4 weeks, 2 days\n= 0 years, 1 month, -1 day"),
        ("2023-01-31", "2023-03-01", false, "Total: 29 days\n\u{2248} 4 weeks, 1 day\n= 0 years, 1 month, -2 days"),
        ("2020-02-29", "2024-02-28", false, "Total: 1,460 days\n\u{2248} 208 weeks, 4 days\n= 3 years, 11 months, 30 days"),
        ("2000-01-01", "2026-09-30", false, "Total: 9,769 days\n\u{2248} 1,395 weeks, 4 days\n= 26 years, 8 months, 29 days"),
        ("2026-09-23", "2026-09-30", false, "Total: 7 days\n\u{2248} 1 week, 0 days\n= 0 years, 0 months, 7 days"),
        ("2026-09-29", "2026-09-30", false, "Total: 1 day\n\u{2248} 0 weeks, 1 day\n= 0 years, 0 months, 1 day"),
        ("2026-05-31", "2026-06-30", false, "Total: 30 days\n\u{2248} 4 weeks, 2 days\n= 0 years, 0 months, 30 days"),
    ])
    func difference(from: String, to: String, inclusive: Bool, expected: String) {
        #expect(ToolDateCalc.difference(from: d(from), to: d(to), inclusive: inclusive, locale: us) == expected)
    }

    // TV: 14 §7.4 add/subtract table
    @Test(arguments: [
        ("2026-09-30", ToolDateOperation.add, "0", ToolDateUnit.days, "Result: 2026-09-30 (Wednesday)\n(+0 days from 2026-09-30)"),
        ("2026-09-30", .add, "10", .days, "Result: 2026-10-10 (Saturday)\n(+10 days from 2026-09-30)"),
        ("2026-09-30", .subtract, "10", .days, "Result: 2026-09-20 (Sunday)\n(-10 days from 2026-09-30)"),
        ("2026-09-30", .add, "1", .days, "Result: 2026-10-01 (Thursday)\n(+1 days from 2026-09-30)"),
        ("2026-09-30", .add, "2", .weeks, "Result: 2026-10-14 (Wednesday)\n(+14 days from 2026-09-30)"),
        ("2026-01-31", .add, "1", .months, "Result: 2026-02-28 (Saturday)\n(+28 days from 2026-01-31)"),
        ("2024-01-31", .add, "1", .months, "Result: 2024-02-29 (Thursday)\n(+29 days from 2024-01-31)"),
        ("2026-03-31", .subtract, "1", .months, "Result: 2026-02-28 (Saturday)\n(-31 days from 2026-03-31)"),
        ("2024-02-29", .add, "1", .years, "Result: 2025-02-28 (Friday)\n(+365 days from 2024-02-29)"),
        ("2024-02-29", .add, "4", .years, "Result: 2028-02-29 (Tuesday)\n(+1,461 days from 2024-02-29)"),
        ("2026-09-30", .add, "-5", .days, "Result: 2026-09-25 (Friday)\n(-5 days from 2026-09-30)"),
        ("2026-09-30", .add, "1000", .days, "Result: 2029-06-26 (Tuesday)\n(+1,000 days from 2026-09-30)"),
    ])
    func add(date: String, op: ToolDateOperation, amount: String, unit: ToolDateUnit, expected: String) {
        #expect(ToolDateCalc.add(date: d(date), operation: op, amountText: amount, unit: unit, locale: us) == expected)
    }

    // TV: 14 §7.4 amount validation (TOOLS-067)
    // TV: DECISIONS "Stage V rulings" (ISO pickers) / V2-DESIGN — the From / To / Date fields use the picker locale,
    // whose short numeric date (the stepper field's format) is `yyyy-MM-dd`, matching the `Result:` line; the
    // system locale (here en_US) would show `10/3/26`.
    @Test func pickerLocaleShowsISODates() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let date = cal.date(from: DateComponents(year: 2026, month: 10, day: 3))!
        func short(_ locale: Locale) -> String {
            let f = DateFormatter()
            f.calendar = cal
            f.timeZone = cal.timeZone
            f.locale = locale
            f.dateStyle = .short
            f.timeStyle = .none
            return f.string(from: date)
        }
        #expect(ToolDateCalc.pickerLocale.identifier == "en_CA")
        #expect(short(ToolDateCalc.pickerLocale) == "2026-10-03")
        #expect(short(us) != "2026-10-03")
        #expect(ToolDateCalc.add(date: d("2026-10-03"), operation: .add, amountText: "0", unit: .days, locale: us)
                .hasPrefix("Result: \(short(ToolDateCalc.pickerLocale)) "))
    }

    @Test func amountValidation() {
        for ok in [" 7 ", "+7", "7", "\t7", "-7"] {
            #expect(ToolDateCalc.add(date: d("2026-09-30"), operation: .add, amountText: ok, unit: .days, locale: us)
                .hasPrefix("Result: "), "\(ok)")
        }
        for bad in ["1,000", "3.5", "1e3", "", "abc", "2147483648", "- 7", "7 7", "++7"] {
            #expect(ToolDateCalc.add(date: d("2026-09-30"), operation: .add, amountText: bad, unit: .days, locale: us)
                == "Enter a whole number.", "\(bad)")
        }
        #expect(ToolNetNumber.parseInt32("2147483647") == Int32.max)
        #expect(ToolNetNumber.parseInt32("-2147483648") == Int32.min)
        #expect(ToolNetNumber.parseInt32("-2147483649") == nil)
        #expect(ToolNetNumber.parseInt32("007") == 7)
    }

    // TV: 14 §7.4 de-DE check
    @Test func germanGrouping() {
        let t = ToolDateCalc.difference(from: d("2000-01-01"), to: d("2026-09-30"), inclusive: false, locale: de)
        #expect(t.hasPrefix("Total: 9.769 days\n\u{2248} 1.395 weeks, 4 days\n"))
        #expect(ToolDateCalc.add(date: d("2026-09-30"), operation: .add, amountText: "0", unit: .days, locale: de)
            == "Result: 2026-09-30 (Mittwoch)\n(+0 days from 2026-09-30)")
    }

    // TV: TOOLS-062/066 empty pickers; DECISIONS 14 Q-16 out of range
    @Test func missingDatesAndOutOfRange() {
        #expect(ToolDateCalc.difference(from: nil, to: d("2026-09-30"), inclusive: false, locale: us) == "Pick both dates.")
        #expect(ToolDateCalc.add(date: nil, operation: .add, amountText: "1", unit: .days, locale: us) == "Pick a date.")
        #expect(ToolDateCalc.add(date: d("9999-12-31"), operation: .add, amountText: "1", unit: .days, locale: us)
            == "Result is out of range.")
        #expect(ToolDateCalc.add(date: d("0001-01-01"), operation: .subtract, amountText: "1", unit: .months, locale: us)
            == "Result is out of range.")
        #expect(ToolDateCalc.add(date: d("2026-09-30"), operation: .add, amountText: "613566757", unit: .weeks, locale: us)
            == "Result is out of range.")
        #expect(ToolDateCalc.add(date: d("2026-09-30"), operation: .subtract, amountText: "-2147483648", unit: .years, locale: us)
            == "Result is out of range.")
        #expect(ToolDateCalc.add(date: d("9999-12-01"), operation: .add, amountText: "30", unit: .days, locale: us)
            == "Result: 9999-12-31 (Friday)\n(+30 days from 9999-12-01)")
        #expect(ToolDateCalc.add(date: d("0001-01-31"), operation: .add, amountText: "1", unit: .months, locale: us)
            == "Result: 0001-02-28 (Wednesday)\n(+28 days from 0001-01-31)")
    }
}
