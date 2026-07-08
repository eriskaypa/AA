using System;
using System.Collections.Generic;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Text;
using AA.Models;
using MigraDoc.DocumentObjectModel;
using MigraDoc.Rendering;
using Section = MigraDoc.DocumentObjectModel.Section;

namespace AA.Services;

/// <summary>Exports the checklist of a <see cref="Procedure"/> on its own (no notes,
/// no relationships, no file bank). PDF is an A4 print-friendly tick sheet;
/// XLSX is a one-sheet workbook with #, Done, Title, Tasks and Equipment/Area columns
/// written directly as the Office Open XML SpreadsheetML format (no third-party deps).</summary>
public static class ChecklistExporter
{
    // ---------- PDF ----------

    public static void ExportPdf(Procedure proc, AppRepository repo, string path)
    {
        var doc = new Document();
        doc.Info.Title = $"Checklist - {proc.Name}";
        doc.Info.Author = "AA";

        var normal = doc.Styles["Normal"]!;
        normal.Font.Name = "Calibri";
        normal.Font.Size = 11;

        var sec = doc.AddSection();
        sec.PageSetup.PageFormat = PageFormat.A4;
        sec.PageSetup.Orientation = Orientation.Portrait;
        sec.PageSetup.TopMargin = "2cm";
        sec.PageSetup.BottomMargin = "2cm";
        sec.PageSetup.LeftMargin = "2cm";
        sec.PageSetup.RightMargin = "2cm";

        var footer = sec.Footers.Primary.AddParagraph();
        footer.Format.Alignment = ParagraphAlignment.Right;
        footer.Format.Font.Size = 9;
        footer.Format.Font.Color = new Color(120, 120, 120);
        footer.AddText("Page ");
        footer.AddPageField();
        footer.AddText(" / ");
        footer.AddNumPagesField();

        var title = sec.AddParagraph(proc.Name);
        title.Format.Font.Size = 22;
        title.Format.Font.Bold = true;
        title.Format.SpaceAfter = "2pt";

        var sub = sec.AddParagraph("Checklist");
        sub.Format.Font.Color = new Color(120, 120, 120);
        sub.Format.SpaceAfter = "10pt";

        if (proc.Steps.Count == 0)
        {
            sec.AddParagraph("(no steps)").Format.Font.Italic = true;
            Render(doc, path);
            return;
        }

        var tbl = sec.AddTable();
        tbl.Borders.Width = 0.5;
        tbl.Borders.Color = new Color(180, 180, 180);
        tbl.LeftPadding = "3pt"; tbl.RightPadding = "3pt"; tbl.TopPadding = "3pt"; tbl.BottomPadding = "3pt";
        tbl.AddColumn("0.9cm");  // #
        tbl.AddColumn("1.0cm");  // Done
        tbl.AddColumn("7.2cm");  // Title
        tbl.AddColumn("2.2cm");  // Due
        tbl.AddColumn("5.0cm");  // Linked tasks / equipment

        var head = tbl.AddRow();
        head.HeadingFormat = true;
        head.Shading.Color = new Color(235, 235, 235);
        head.Cells[0].AddParagraph("#").Format.Font.Bold = true;
        head.Cells[1].AddParagraph("Done").Format.Font.Bold = true;
        head.Cells[2].AddParagraph("Step").Format.Font.Bold = true;
        head.Cells[3].AddParagraph("Due").Format.Font.Bold = true;
        head.Cells[4].AddParagraph("Tasks / Equipment-Area").Format.Font.Bold = true;

        int n = 1;
        foreach (var s in proc.Steps)
        {
            var r = tbl.AddRow();
            r.Cells[0].AddParagraph(n++.ToString());
            r.Cells[1].AddParagraph(s.Done ? "[x]" : "[  ]");
            r.Cells[2].AddParagraph(s.Title ?? "");
            r.Cells[3].AddParagraph(s.Deadline?.ToString("yyyy-MM-dd") ?? "");
            var refs = new List<string>();
            foreach (var id in s.TaskIds)
            {
                var t = repo.FindById(id); if (t != null) refs.Add("T: " + t.Name);
            }
            foreach (var id in s.EquipmentIds)
            {
                var e = repo.FindById(id); if (e != null) refs.Add("E/A: " + e.Name);
            }
            r.Cells[4].AddParagraph(refs.Count == 0 ? "" : string.Join("\n", refs));
        }

        Render(doc, path);
    }

    private static void Render(Document doc, string path)
    {
        var renderer = new PdfDocumentRenderer { Document = doc };
        renderer.RenderDocument();
        renderer.PdfDocument.Save(path);
    }

    // ---------- XLSX (minimal Office Open XML SpreadsheetML, zero external dependencies) ----------

    public static void ExportXlsx(Procedure proc, AppRepository repo, string path)
    {
        var rows = new List<string[]>
        {
            new[] { "#", "Done", "Step", "Due", "Linked Tasks", "Linked Equipment/Area" }
        };
        int n = 1;
        foreach (var s in proc.Steps)
        {
            var tasks = string.Join("; ", s.TaskIds.Select(id => repo.FindById(id)?.Name).Where(x => x != null));
            var eqs = string.Join("; ", s.EquipmentIds.Select(id => repo.FindById(id)?.Name).Where(x => x != null));
            rows.Add(new[] { n++.ToString(), s.Done ? "Yes" : "No", s.Title ?? "", s.Deadline?.ToString("yyyy-MM-dd") ?? "", tasks, eqs });
        }

        if (File.Exists(path)) File.Delete(path);
        using var fs = new FileStream(path, FileMode.CreateNew);
        using var zip = new ZipArchive(fs, ZipArchiveMode.Create);
        WriteEntry(zip, "[Content_Types].xml", ContentTypesXml());
        WriteEntry(zip, "_rels/.rels", RootRelsXml());
        WriteEntry(zip, "xl/workbook.xml", WorkbookXml(proc.Name));
        WriteEntry(zip, "xl/_rels/workbook.xml.rels", WorkbookRelsXml());
        WriteEntry(zip, "xl/styles.xml", StylesXml());
        WriteEntry(zip, "xl/worksheets/sheet1.xml", SheetXml(rows));
    }

    private static void WriteEntry(ZipArchive zip, string entryName, string content)
    {
        var e = zip.CreateEntry(entryName, CompressionLevel.Optimal);
        using var s = e.Open();
        var bytes = Encoding.UTF8.GetBytes(content);
        s.Write(bytes, 0, bytes.Length);
    }

    private static string ContentTypesXml() => """
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
  <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
  <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
</Types>
""";

    private static string RootRelsXml() => """
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
</Relationships>
""";

    private static string WorkbookXml(string sheetName)
    {
        var safe = Esc(string.IsNullOrWhiteSpace(sheetName) ? "Checklist" : sheetName);
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

    private static string WorkbookRelsXml() => """
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
  <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
</Relationships>
""";

    private static string StylesXml() => """
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

    private static string SheetXml(List<string[]> rows)
    {
        var sb = new StringBuilder();
        sb.AppendLine("<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>");
        sb.AppendLine("<worksheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\">");
        sb.AppendLine("<cols>");
        sb.AppendLine("<col min=\"1\" max=\"1\" width=\"5\" customWidth=\"1\"/>");
        sb.AppendLine("<col min=\"2\" max=\"2\" width=\"7\" customWidth=\"1\"/>");
        sb.AppendLine("<col min=\"3\" max=\"3\" width=\"55\" customWidth=\"1\"/>");
        sb.AppendLine("<col min=\"4\" max=\"4\" width=\"14\" customWidth=\"1\"/>");
        sb.AppendLine("<col min=\"5\" max=\"5\" width=\"40\" customWidth=\"1\"/>");
        sb.AppendLine("<col min=\"6\" max=\"6\" width=\"40\" customWidth=\"1\"/>");
        sb.AppendLine("</cols>");
        sb.AppendLine("<sheetData>");
        for (int r = 0; r < rows.Count; r++)
        {
            sb.Append("<row r=\"").Append(r + 1).Append("\">");
            var row = rows[r];
            var styleId = r == 0 ? 1 : 0;
            for (int c = 0; c < row.Length; c++)
            {
                var cellRef = ColRef(c) + (r + 1);
                sb.Append("<c r=\"").Append(cellRef).Append("\" t=\"inlineStr\" s=\"").Append(styleId).Append("\"><is><t xml:space=\"preserve\">")
                  .Append(Esc(row[c] ?? "")).Append("</t></is></c>");
            }
            sb.AppendLine("</row>");
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

    private static string Esc(string s) => s
        .Replace("&", "&amp;")
        .Replace("<", "&lt;")
        .Replace(">", "&gt;")
        .Replace("\"", "&quot;");
}
