using System.Collections.Generic;
using System.IO;
using System.IO.Compression;
using System.Text;

namespace AA.Services;

/// <summary>Minimal, dependency-free Office Open XML (SpreadsheetML) writer: one sheet, string cells,
/// a bold shaded header row. Same on-disk format the checklist exporter uses, generalised so any
/// header + rows can be written (used by the crew table export).</summary>
public static class XlsxWriter
{
    /// <summary>Write a single-sheet .xlsx. <paramref name="headers"/> is the (bold) first row; each row in
    /// <paramref name="rows"/> should have the same length as <paramref name="headers"/> (short/long rows are
    /// tolerated). Overwrites <paramref name="path"/>.</summary>
    public static void Write(string path, string sheetName, IReadOnlyList<string> headers, IReadOnlyList<string[]> rows)
    {
        var all = new List<string[]>(rows.Count + 1) { headers.ToArrayCopy() };
        all.AddRange(rows);

        if (File.Exists(path)) File.Delete(path);
        using var fs = new FileStream(path, FileMode.CreateNew);
        using var zip = new ZipArchive(fs, ZipArchiveMode.Create);
        WriteEntry(zip, "[Content_Types].xml", ContentTypesXml);
        WriteEntry(zip, "_rels/.rels", RootRelsXml);
        WriteEntry(zip, "xl/workbook.xml", WorkbookXml(sheetName));
        WriteEntry(zip, "xl/_rels/workbook.xml.rels", WorkbookRelsXml);
        WriteEntry(zip, "xl/styles.xml", StylesXml);
        WriteEntry(zip, "xl/worksheets/sheet1.xml", SheetXml(all, headers.Count));
    }

    private static string[] ToArrayCopy(this IReadOnlyList<string> list)
    {
        var a = new string[list.Count];
        for (int i = 0; i < list.Count; i++) a[i] = list[i];
        return a;
    }

    private static void WriteEntry(ZipArchive zip, string entryName, string content)
    {
        var e = zip.CreateEntry(entryName, CompressionLevel.Optimal);
        using var s = e.Open();
        var bytes = Encoding.UTF8.GetBytes(content);
        s.Write(bytes, 0, bytes.Length);
    }

    private const string ContentTypesXml = """
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
  <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
  <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
</Types>
""";

    private const string RootRelsXml = """
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
</Relationships>
""";

    private const string WorkbookRelsXml = """
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
  <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
</Relationships>
""";

    private const string StylesXml = """
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <fonts count="2">
    <font><sz val="11"/><name val="Calibri"/></font>
    <font><b/><sz val="11"/><name val="Calibri"/></font>
  </fonts>
  <fills count="2">
    <fill><patternFill patternType="none"/></fill>
    <fill><patternFill patternType="solid"><fgColor rgb="FFEEEEEE"/><bgColor indexed="64"/></patternFill></fill>
  </fills>
  <borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>
  <cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
  <cellXfs count="2">
    <xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>
    <xf numFmtId="0" fontId="1" fillId="1" borderId="0" xfId="0" applyFont="1" applyFill="1"/>
  </cellXfs>
  <cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>
</styleSheet>
""";

    private static string WorkbookXml(string sheetName)
    {
        var safe = Esc(string.IsNullOrWhiteSpace(sheetName) ? "Sheet1" : sheetName);
        if (safe.Length > 31) safe = safe.Substring(0, 31);
        return $"""
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <sheets>
    <sheet name="{safe}" sheetId="1" r:id="rId1"/>
  </sheets>
</workbook>
""";
    }

    private static string SheetXml(List<string[]> rows, int colCount)
    {
        var sb = new StringBuilder();
        sb.AppendLine("<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>");
        sb.AppendLine("<worksheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\">");
        if (colCount > 0)
        {
            sb.AppendLine("<cols>");
            sb.Append("<col min=\"1\" max=\"").Append(colCount).Append("\" width=\"20\" customWidth=\"1\"/>\n");
            sb.AppendLine("</cols>");
        }
        sb.AppendLine("<sheetData>");
        for (int r = 0; r < rows.Count; r++)
        {
            sb.Append("<row r=\"").Append(r + 1).Append("\">");
            var row = rows[r];
            var styleId = r == 0 ? 1 : 0;   // header row bold+shaded
            for (int c = 0; c < row.Length; c++)
            {
                var cellRef = ColRef(c) + (r + 1);
                sb.Append("<c r=\"").Append(cellRef).Append("\" t=\"inlineStr\" s=\"").Append(styleId)
                  .Append("\"><is><t xml:space=\"preserve\">").Append(Esc(row[c] ?? "")).Append("</t></is></c>");
            }
            sb.Append("</row>\n");
        }
        sb.AppendLine("</sheetData>");
        sb.AppendLine("</worksheet>");
        return sb.ToString();
    }

    private static string ColRef(int index)
    {
        index += 1;
        var sb = new StringBuilder();
        while (index > 0)
        {
            int rem = (index - 1) % 26;
            sb.Insert(0, (char)('A' + rem));
            index = (index - 1) / 26;
        }
        return sb.ToString();
    }

    private static string Esc(string s)
    {
        if (string.IsNullOrEmpty(s)) return "";
        var sb = new StringBuilder(s.Length);
        foreach (var ch in s)
        {
            // Drop characters that are illegal in XML 1.0 (keeps tab/LF/CR) so a stray control char in
            // imported crew data can't produce an unopenable workbook.
            if (ch < 0x20 && ch != '\t' && ch != '\n' && ch != '\r') continue;
            switch (ch)
            {
                case '&': sb.Append("&amp;"); break;
                case '<': sb.Append("&lt;"); break;
                case '>': sb.Append("&gt;"); break;
                case '"': sb.Append("&quot;"); break;
                default: sb.Append(ch); break;
            }
        }
        return sb.ToString();
    }
}
