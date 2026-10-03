// Tests for 14 §7.5 (unit converter: seed rows, targeted conversions, .NET NumberStyles.Any parsing, .NET G6 /
// "0.######" formatting), TOOLS-081…088.
import Foundation
import Testing
@testable import AACore

@Suite struct ToolUnitConverterTests {
    // TV: 14 §3.5.3 totals
    @Test func catalogShape() {
        let cats = ToolUnitCatalog.categories
        #expect(cats.map(\.name) == ["Speed", "Distance / Length", "Pressure", "Temperature", "Volume", "Mass / Weight",
                                     "Angle / Bearing", "Time", "Power", "Force", "Density", "Flow rate", "Area", "Energy"])
        #expect(cats.map(\.units.count) == [6, 10, 10, 3, 8, 7, 6, 6, 5, 5, 4, 6, 5, 5])
        #expect(cats.reduce(0) { $0 + $1.units.count } == 86)
        #expect(cats[2].units[6].name == "kg-force / cm\u{00B2}")
        #expect(cats[3].units.map(\.name) == ["Celsius (\u{00B0}C)", "Fahrenheit (\u{00B0}F)", "Kelvin (K)"])
        #expect(cats[6].units[5].name == "Arcminutes (')")
        #expect(ToolUnitCatalog.note == "Type a value in any unit \u{2014} every other unit updates instantly. Maritime-focused units included.")
    }

    // TV: 14 §7.5.1 seed rows
    @Test func seedRows() {
        let expected: [[String]] = [
            ["1", "1.851997", "1.150778", "0.514444", "1.687808", "23.999979"],
            ["1", "1.150779", "1.852", "1852", "10", "1012.685914", "2025.371829", "6076.115486", "72913.385827", "185200"],
            ["1", "1000", "14.503774", "100", "0.1", "0.986923", "1.019716", "750.061578", "29.52998", "100000"],
            ["1", "33.8", "274.15"],
            ["1", "0.001", "0.035315", "0.264172", "0.219969", "0.00629", "1.056688", "1000"],
            ["1", "0.001", "0.000984", "0.001102", "2.204623", "0.157473", "1000"],
            ["1", "0.017453", "1.111111", "0.088889", "17.777778", "60"],
            ["1", "0.016667", "0.000278", "1.15741E-05", "1.65344E-06", "6.94444E-05"],
            ["1", "1000", "1.359622", "1.341022", "3412.141635"],
            ["1", "0.001", "0.000102", "0.101972", "0.224809"],
            ["1", "0.001", "0.062428", "0.008345"],
            ["1", "24", "16.666667", "1000", "4.402868", "150.955458"],
            ["1", "1E-06", "0.0001", "10.76391", "0.000247"],
            ["1", "1000", "0.000278", "0.239006", "0.947817"],
        ]
        var s = ToolUnitConverterState()
        #expect(s.categoryIndex == 0)
        for (i, rows) in expected.enumerated() {
            s.selectCategory(i)
            #expect(s.texts == rows, "category \(ToolUnitCatalog.categories[i].name)")
        }
    }

    private func convert(_ category: Int, _ row: Int, _ text: String) -> [String] {
        var s = ToolUnitConverterState(categoryIndex: category)
        s.edit(row: row, text: text)
        return s.texts
    }

    // TV: 14 §7.5.2
    @Test func targetedConversions() {
        #expect(convert(3, 0, "100") == ["100", "212", "373.15"])
        #expect(convert(3, 1, "-40") == ["-40", "-40", "233.15"])
        #expect(convert(3, 2, "0") == ["-273.15", "-459.67", "0"])
        #expect(convert(3, 1, "98.6")[0] == "37")
        let kn = convert(0, 0, "15")
        #expect(kn[1] == "27.779954" && kn[5] == "359.999689")
        #expect(convert(0, 1, "1")[0] == "0.539958")
        #expect(convert(1, 4, "1")[0] == "0.1")
        #expect(convert(1, 5, "100")[3] == "182.88")
        #expect(convert(2, 0, "1e7")[9] == "1E+12")
        #expect(convert(2, 0, "1e-10")[9] == "1E-05")
        #expect(convert(2, 9, "1")[4] == "1E-06")
        #expect(convert(6, 3, "8")[0] == "90")
        #expect(convert(6, 1, "3.14159265358979")[0] == "180")
        #expect(convert(7, 5, "6")[2] == "24")
        #expect(convert(7, 3, "1")[5] == "6")
        #expect(convert(5, 2, "1")[4] == "2239.999981")
        #expect(convert(5, 3, "1")[4] == "2000")
        #expect(convert(4, 5, "1")[3] == "41.999998")
        #expect(convert(4, 1, "1")[5] == "6.289811")
        #expect(convert(11, 5, "1000")[0] == "6.624471")
    }

    // TV: 14 §7.5.2 parsing rows
    @Test func parsingThroughTheConverter() {
        #expect(convert(0, 0, "1,5")[1] == "27.779954")
        #expect(convert(1, 3, "(5)")[3] == "(5)")
        #expect(convert(1, 3, "(5)")[2] == "-0.005")
        #expect(convert(1, 3, "5-")[2] == "-0.005")
        #expect(convert(1, 3, "1e3")[2] == "1")
        #expect(convert(1, 3, " 2.5 ")[9] == "250")
        #expect(convert(1, 3, "\u{00A4}3")[9] == "300")
        for bad in ["", "-", ".", "1e", "e3", ",5", "abc", "1.2.3", "0x10"] {
            let t = convert(1, 3, bad)
            #expect(t[3] == bad)
            #expect(t.enumerated().allSatisfy { $0.offset == 3 || $0.element.isEmpty }, "\(bad)")
        }
        #expect(convert(1, 3, "1,,2")[2] == "0.012")
        #expect(convert(1, 3, "1,000.5")[2] == "1.0005")
        for special in ["NaN", "Infinity", "1e400"] {
            let t = convert(1, 3, special)
            #expect(t.enumerated().allSatisfy { $0.offset == 3 || $0.element.isEmpty }, "\(special)")
        }
    }

    // TV: TOOLS-083/085/088
    @Test func editedRowIsNeverRewrittenAndSwitchReseeds() {
        var s = ToolUnitConverterState()
        s.edit(row: 2, text: "10.50")
        #expect(s.texts[2] == "10.50")
        #expect(s.texts[3] == "4.69392")
        s.edit(row: 2, text: "")
        #expect(s.texts == ["", "", "", "", "", ""])
        s.selectCategory(3)
        #expect(s.texts == ["1", "33.8", "274.15"])
        s.selectCategory(99)                                   // ignored
        #expect(s.categoryIndex == 3)
    }

    // TV: 14 §3.5.2 grammar details
    @Test func netDoubleParser() {
        let p = ToolNetNumber.parseDouble
        #expect(p("1,5") == 15)
        #expect(p("(5)") == -5)
        #expect(p("5-") == -5)
        #expect(p("+5") == 5)
        #expect(p("5+") == 5)
        #expect(p("1e3") == 1000)
        #expect(p("1E+3") == 1000)
        #expect(p("2.5e-1") == 0.25)
        #expect(p(" 2.5 ") == 2.5)
        #expect(p("\t7\n") == 7)
        #expect(p("\u{00A4}3") == 3)
        #expect(p("3\u{00A4}") == 3)
        #expect(p("-\u{00A4}3") == -3)
        #expect(p(".5") == 0.5)
        #expect(p("5.") == 5)
        #expect(p("1,2,3") == 123)
        #expect(p("1,,2") == 12)
        #expect(p("1,") == 1)
        #expect(p("1,000.5") == 1000.5)
        #expect(p("1e400") == .infinity)
        #expect(p("-1e400") == -.infinity)
        #expect(p("1e-400") == 0)
        #expect(p("0") == 0)
        #expect(p("-0")?.sign == .minus)
        #expect(p("infinity") == .infinity)
        #expect(p("-INFINITY") == -.infinity)
        #expect(p("+Infinity") == .infinity)
        #expect(p(" NaN ")?.isNaN == true)
        #expect(p("-nan")?.isNaN == true)
        #expect(p("+NaN")?.isNaN == true)
        for bad in ["", " ", "-", ".", "1e", "e3", ",5", "abc", "1.2.3", "0x10", "1.2,3", "- 5", "(5", "5)", "(-5)",
                    "--5", "5 5", "1e+", "Inf"] {
            #expect(p(bad) == nil, "\(bad)")
        }
        #expect(p("0.1") == 0.1)
        #expect(p("123456789012345678901234567890") == 123456789012345678901234567890.0)
    }

    // TV: 14 §7.5.3
    @Test func netDoubleFormatter() {
        let f = ToolNetDoubleFormat.unitConverterText
        #expect(f(0) == "0")
        #expect(f(-0.0) == "0")
        #expect(f(0.30000000000000004) == "0.3")
        #expect(f(0.1234565) == "0.123457")
        #expect(f(0.5000005) == "0.500001")
        #expect(f(5.0000015) == "5.000002")
        #expect(f(1234567.8912345) == "1234567.891235")
        #expect(f(999999999999.9) == "999999999999.9")
        #expect(f(1e12) == "1E+12")
        #expect(f(123456789012345.0) == "1.23457E+14")
        #expect(f(1e21) == "1E+21")
        #expect(f(0.00001234) == "1.234E-05")
        #expect(f(-1e-5) == "-1E-05")
        #expect(f(2.5e-7) == "2.5E-07")
        #expect(f(9.999996e-5) == "0.0001")
        #expect(f(0.0001) == "0.0001")
        #expect(f(-0.5) == "-0.5")
        #expect(f(.nan) == "")
        #expect(f(.infinity) == "")
        #expect(f(-.infinity) == "")
        #expect(f(1e100) == "1E+100")
        #expect(f(-123.4567894) == "-123.456789")
        #expect(f(0.9999999) == "1")
        #expect(f(99.99999951) == "100")
    }
}
