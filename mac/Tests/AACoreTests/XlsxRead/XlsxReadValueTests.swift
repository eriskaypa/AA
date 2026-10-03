// Tests for 10 Addendum X.8.2 (custom-format classification), X.8.3 (serials), X.8.4 (durations), X.8.5 (number
// text), X.8.6 (strings).
import Foundation
import Testing
@testable import AACore

@Suite struct XlsxReadValueTests {
    @Test func classifyCustomCodes() {
        // TV: 10 X.8.2
        let number = ["General", "@", "0.00", "#,##0", "# ?/?", "0.00E+00", "[Red]0.00;[Blue]-0.00", "\"Day \"0",
                      "_(* #,##0.00_)", ";;;", "\"abc", "[Red", "   "]
        for code in number { #expect(XlsxStyles.classifyCustom(code) == .number, "\(code)") }
        let date = ["dd/mm/yyyy", "m/d/yyyy", "mmm-yy", "mmmm", "yyyy-mm-dd h:mm", "[$-409]d-mmm-yy;@",
                    "[$-F800]dddd, mmmm dd, yyyy", "yyyy\"年\"m\"月\"d\"日\"", "\\d0", "AM/PM h:mm", "[h]:mm"]
        for code in date { #expect(XlsxStyles.classifyCustom(code) == .dateTime, "\(code)") }
        let time = ["h:mm", "hh:mm:ss AM/PM", "[h]:mm:ss", "mm:ss", "mm:ss.0", "[mm]:ss", "ss"]
        for code in time { #expect(XlsxStyles.classifyCustom(code) == .timeSpan, "\(code)") }
        #expect(XlsxStyles.builtinKind(14) == .dateTime && XlsxStyles.builtinKind(22) == .dateTime)
        #expect(XlsxStyles.builtinKind(17) == .number && XlsxStyles.builtinKind(30) == .number)
        #expect(XlsxStyles.builtinKind(49) == .number && XlsxStyles.builtinKind(55) == .number)
        for id in [18, 19, 20, 21, 45, 46, 47] { #expect(XlsxStyles.builtinKind(id) == .timeSpan) }
    }

    @Test func numFmtOverrides() throws {
        // TV: 10 X.8.2 last three rows (override wins; an empty override is ignored)
        let book = SvcXlsxTestBook(sheetData: "<row r=\"1\"><c r=\"A1\" s=\"1\"><v>45000</v></c><c r=\"B1\" s=\"2\"><v>45000</v></c><c r=\"C1\" s=\"3\"><v>45000</v></c></row>",
                                   xfs: [0, 14, 20, 15],
                                   numFmts: [(14, "0.00"), (20, "yyyy-mm-dd"), (15, "")])
        let (_, s) = try book.firstSheet()
        #expect(s.cell(1, 1).value == .number(45000))
        #expect(s.cell(1, 2).value == .dateTime(serial: 45000))
        #expect(s.cell(1, 3).value == .dateTime(serial: 45000))
    }

    @Test func serials() throws {
        // TV: 10 X.8.3 (direct conversions)
        func a(_ v: Double) throws -> String { try ExcelSerial.fromSerial(v).format(.isoDate) }
        #expect(try a(0) == "1899-12-31" && a(1) == "1900-01-01" && a(59) == "1900-02-28")
        #expect(try a(60) == "1900-03-01" && a(61) == "1900-03-01" && a(46085) == "2026-03-04" && a(46096) == "2026-03-15")
        #expect(throws: XlsxReadError.message("Serial date 60 is on a leap year of 1900 - date that doesn't exist and isn't representable in DateTime.")) {
            _ = try ExcelSerial.fromSerial(60.5)
        }
        #expect(try a(2958465.999999) == "9999-12-31")
        #expect(throws: XlsxReadError.message("Not a legal OleAut date.")) { _ = try ExcelSerial.fromSerial(2958466) }
        #expect(throws: XlsxReadError.message("Not a legal OleAut date.")) { _ = try ExcelSerial.fromOADate(-657435) }
        func c(_ v: Double) throws -> String {
            try XlsxRender.portsCell(XlsxCell(value: .dateTime(serial: v)), workbook: XlsxWorkbook(worksheets: [], use1904: false))
        }
        #expect(try c(46218.99999999) == "2026-07-15 23:59")
        #expect(try c(46218.999999999) == "2026-07-16")
        #expect(try c(-1.25) == "1899-12-30 06:00")
        #expect(try c(-0.25) == "1899-12-30 18:00")
        // ExcelDate serial window (10 §7.8)
        let today = CivilDate(iso: "2026-09-29")!
        #expect(ShippalmDates.excelDate("48108", today: today) == "2031-09-17")
        #expect(ShippalmDates.excelDate("46218", today: today) == "2026-07-15")
        #expect(ShippalmDates.excelDate("20001", today: today) == "1954-10-04")
        #expect(ShippalmDates.excelDate("15000", today: today) == "15000")
        // round trip toSerial ∘ fromSerial
        for v in [1.0, 59, 61, 45000.75, 46218.5] {
            #expect(ExcelSerial.toSerial(try ExcelSerial.fromSerial(v)) == v)
        }
    }

    @Test func serialsInSheets() throws {
        // TV: 10 X.8.3 sheet rows (1904, t="d")
        let rows = """
        <row r="1"><c r="A1" s="1"><v>44623</v></c><c r="B1" s="1"><v>45000</v></c><c r="C1" s="1"><v>0</v></c><c r="D1"><v>44623</v></c><c r="E1" t="d"><v>2026-03-04</v></c></row>
        """
        let b1904 = SvcXlsxTestBook(sheetData: rows, xfs: [0, 14], date1904: true)
        let (wb, s) = try b1904.firstSheet()
        #expect(wb.use1904)
        #expect(try XlsxRender.compasCellString(s.cell(1, 1), workbook: wb) == "2026-03-04")
        #expect(try XlsxRender.compasCellString(s.cell(1, 2), workbook: wb) == "2027-03-16")
        #expect(try XlsxRender.compasCellString(s.cell(1, 3), workbook: wb) == "1904-01-02")
        let d1 = s.cell(1, 4)
        #expect(try XlsxRender.compasCellString(d1, workbook: wb) == "44623")
        #expect(XlsxRender.shippalmExcelDate(try XlsxRender.shippalmCell(d1, workbook: wb), today: CivilDate(iso: "2026-09-29")!) == "2022-03-03")
        #expect(try XlsxRender.portsCell(d1, workbook: wb) == "44623")
        #expect(try XlsxRender.compasCellString(s.cell(1, 5), workbook: wb) == "2030-03-05")

        let iso = SvcXlsxTestBook(sheetData: """
        <row r="1"><c r="A1" t="d"><v>2026-03-04</v></c><c r="B1" t="d"><v> 2026-03-04T10:30 </v></c><c r="C1" t="d"><v>2026-03-04T10:30:00.000</v></c></row>
        """)
        let (wb2, s2) = try iso.firstSheet()
        #expect(try XlsxRender.compasCellString(s2.cell(1, 1), workbook: wb2) == "2026-03-04")
        #expect(try XlsxRender.compasCellString(s2.cell(1, 2), workbook: wb2) == "2026-03-04")
        #expect(try XlsxRender.portsCell(s2.cell(1, 2), workbook: wb2) == "2026-03-04 10:30")
        #expect(try XlsxRender.portsCell(s2.cell(1, 3), workbook: wb2) == "2026-03-04 10:30")
        let bad = SvcXlsxTestBook(sheetData: "<row r=\"1\"><c r=\"A1\" t=\"d\"><v>2026-03-04T10:30:00</v></c></row>")
        #expect(throws: XlsxReadError.self) { _ = try bad.firstSheet() }
        do { _ = try bad.firstSheet() } catch let e as XlsxReadError {
            #expect(e.errorDescription?.hasPrefix("The file could not be opened as an Excel workbook (.xlsx).") == true)
        }
        let leap1904 = SvcXlsxTestBook(sheetData: "<row r=\"1\"><c r=\"A1\" s=\"1\"><v>60.5</v></c></row>", xfs: [0, 14], date1904: true)
        #expect(throws: XlsxReadError.self) { _ = try leap1904.firstSheet() }
    }

    @Test func durations() throws {
        // TV: 10 X.8.4
        let vectors: [(Double, Int64, String, String)] = [
            (0, 0, "0:00:00", "00:00"), (0.25, 21_600_000, "6:00:00", "06:00"), (0.5, 43_200_000, "12:00:00", "12:00"),
            (0.500001, 43_200_086, "12:00:00.086", "12:00"), (0.999999, 86_399_914, "23:59:59.914", "23:59"),
            (1.5, 129_600_000, "36:00:00", "12:00"),
            (43_200_200.0 / 86_400_000.0, 43_200_200, "12:00:00.2", "12:00"),
            (43_200_250.0 / 86_400_000.0, 43_200_250, "12:00:00.25", "12:00"),
            (48_655_200.0 / 86_400_000.0, 48_655_200, "13:30:55.2", "13:30"),
        ]
        for (serial, ms, a, c) in vectors {
            #expect(try ExcelSerial.toTimeSpanMs(serial) == ms, "\(serial)")
            #expect(ExcelSerial.excelString(ms: ms) == a)
            #expect(ExcelSerial.hoursMinutes(ms: ms) == c)
            let cell = XlsxCell(value: .timeSpan(serial: serial))
            let wb = XlsxWorkbook(worksheets: [], use1904: false)
            #expect(try XlsxRender.compasCellString(cell, workbook: wb) == a)
            #expect(try XlsxRender.portsCell(cell, workbook: wb) == c)
            #expect(XlsxRender.getString(cell) == a)
        }
        #expect(throws: XlsxReadError.self) { _ = try ExcelSerial.toTimeSpanMs(1e20) }
    }

    @Test func numberTexts() {
        // TV: 10 X.8.5 (A/B integral-or-shortest, C "0.####")
        let wb = XlsxWorkbook(worksheets: [], use1904: false)
        let vectors: [(Double, String, String)] = [
            (12345.0, "12345", "12345"), (180.5, "180.5", "180.5"), (0.1 + 0.2, "0.30000000000000004", "0.3"),
            (1e-7, "1E-07", "0"), (0.0001, "0.0001", "0.0001"), (0.00001234, "1.234E-05", "0"), (0.00005, "5E-05", "0.0001"),
            (2.00005, "2.00005", "2.0001"), (1234.56785, "1234.56785", "1234.5679"), (1234.56789, "1234.56789", "1234.5679"),
            (-3, "-3", "-3"), (-1.5, "-1.5", "-1.5"), (-0.0, "0", "0"), (-0.00001, "-1E-05", "0"),
            (9_792_606, "9792606", "9792606"), (123_456_789_012_345.6, "123456789012345.6", "123456789012346"),
            (1_000_000_000_000_000.5, "1.0000000000000005E+15", "1000000000000000"),
            (12_345_678_901_234_568, "12345678901234568", "12345678901234600"),
            (1e20, "9223372036854775807", "100000000000000000000"),
        ]
        for (v, a, c) in vectors {
            let cell = XlsxCell(value: .number(v))
            #expect((try? XlsxRender.compasCellString(cell, workbook: wb)) == a, "\(v)")
            #expect((try? XlsxRender.portsCell(cell, workbook: wb)) == c, "\(v)")
        }
        #expect(XlsxRender.getString(XlsxCell(value: .number(1e20))) == "1E+20")
    }

    @Test func strings() throws {
        // TV: 10 X.8.6
        let sst = ["<t>Hello</t>",
                   "<r><t xml:space=\"preserve\">Hello </t></r><r><rPr><b/></rPr><t>World</t></r><rPh sb=\"0\" eb=\"1\"><t>ハロー</t></rPh><phoneticPr fontId=\"1\"/>",
                   "<t>東京</t><rPh sb=\"0\" eb=\"2\"><t>トウキョウ</t></rPh>",
                   "<t>A_x000D_&#10;B</t>",
                   "<t>Line1&#10;Line2</t>",
                   "<r><t>Line1&#10;Line2</t></r>",
                   "<t>_x005F_x000D_</t>",
                   "<t>_X000D_</t>",
                   "<t>_x0041__x0042_</t>",
                   "<t>_xD83D__xDE00_</t>",
                   "<t xml:space=\"preserve\">   </t>",
                   "<t>_x0001F600_</t>",
                   "<t>_xD800_</t>",
                   "<t>a&#13;b</t>"]
        var cells = sst.indices.map { "<c r=\"A\($0 + 1)\" t=\"s\"><v>\($0)</v></c>" }.joined()
        cells += "<c r=\"B1\" t=\"inlineStr\"><is><t>A&#10;B</t></is></c>"
        cells += "<c r=\"B2\" t=\"inlineStr\"><is><t>A_x000D_B</t></is></c>"
        cells += "<c r=\"B3\" t=\"str\"><f>A1</f><v>  x  </v></c>"
        cells += "<c r=\"B4\" t=\"s\"/>"
        cells += "<c r=\"B5\" t=\"s\"><v>999</v></c>"
        cells += "<c r=\"B6\" t=\"inlineStr\"><is><r><t>x&#10;</t></r><r><t>y</t></r></is></c>"
        cells += "<c r=\"B7\" t=\"inlineStr\"><is/></c>"
        let (wb, s) = try SvcXlsxTestBook(sheetData: "<row r=\"1\">\(cells)</row>", sharedStrings: sst).firstSheet()
        // all cells were placed in row 1 by their own references
        func text(_ r: Int, _ c: Int) -> XlsxValue { s.cell(r, c).value }
        #expect(text(1, 1) == .text("Hello"))
        #expect(text(2, 1) == .text("Hello World"))
        #expect(text(3, 1) == .text("東京"))
        #expect(text(4, 1) == .text("A\r\nB"))
        #expect(text(5, 1) == .text("Line1\nLine2"))
        #expect(text(6, 1) == .text("Line1\r\nLine2"))
        #expect(text(7, 1) == .text("_x000D_"))
        #expect(text(8, 1) == .text("_X000D_"))
        #expect(text(9, 1) == .text("AB"))
        #expect(text(10, 1) == .text("😀"))
        #expect(text(11, 1) == .text("   "))
        #expect(text(12, 1) == .text("😀"))
        #expect(text(13, 1) == .text("\u{FFFD}"))
        #expect(text(14, 1) == .text("a\rb"))
        #expect(try XlsxRender.compasCellString(s.cell(4, 1), workbook: wb) == "A\r\nB")
        #expect(try XlsxRender.compasCellString(s.cell(11, 1), workbook: wb) == "")
        #expect(!s.cell(11, 1).isEmpty)
        #expect(text(1, 2) == .text("A\r\nB"))
        #expect(text(2, 2) == .text("A_x000D_B"))
        #expect(text(3, 2) == .text("  x  ") && s.cell(3, 2).hasFormula)
        #expect(try XlsxRender.portsCell(s.cell(3, 2), workbook: wb) == "x")
        #expect(text(4, 2) == .text("") && s.cell(4, 2).isEmpty)
        #expect(text(5, 2) == .text(""))
        #expect(text(6, 2) == .text("x\r\ny"))
        #expect(text(7, 2) == .text("") && s.cell(7, 2).isEmpty)
    }

    @Test func numberParsing() throws {
        // X.4.5 parseNumber / parseIndex
        #expect(try SvcXlsxSheet.parseNumber(" 1.5e3 ") == 1500)
        #expect(try SvcXlsxSheet.parseNumber(".5") == 0.5 && SvcXlsxSheet.parseNumber("5.") == 5)
        #expect(try SvcXlsxSheet.parseNumber("-0") == 0 && SvcXlsxSheet.parseNumber("+2") == 2)
        #expect(try SvcXlsxSheet.parseNumber("1,234") == nil && SvcXlsxSheet.parseNumber("abc") == nil)
        #expect(try SvcXlsxSheet.parseNumber(".") == nil && SvcXlsxSheet.parseNumber("1e") == nil && SvcXlsxSheet.parseNumber("0x10") == nil)
        #expect(throws: XlsxReadError.self) { _ = try SvcXlsxSheet.parseNumber("NaN") }
        #expect(throws: XlsxReadError.self) { _ = try SvcXlsxSheet.parseNumber("-Infinity") }
        #expect(throws: XlsxReadError.self) { _ = try SvcXlsxSheet.parseNumber("1e400") }
        #expect(SvcXlsxSheet.parseIndex("3") == 3 && SvcXlsxSheet.parseIndex("3.0") == 3 && SvcXlsxSheet.parseIndex("3.5") == nil)
        #expect(SvcXlsxSheet.parseIndex("-1") == nil && SvcXlsxSheet.parseIndex("1e1") == 10)
        #expect(ShippalmDates.numberAny("(1,234.5)") == -1234.5 && ShippalmDates.numberAny(" 46218 ") == 46218)
        #expect(ShippalmDates.numberAny("46218-") == -46218 && ShippalmDates.numberAny("\u{00A4}46,218") == 46218)
        #expect(ShippalmDates.numberAny("x") == nil && ShippalmDates.numberAny("1.2,3") == nil)
    }
}
