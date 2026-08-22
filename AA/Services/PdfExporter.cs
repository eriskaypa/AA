using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using System.Windows.Documents;
using System.Windows.Markup;
using AA.Models;
using MigraDoc.DocumentObjectModel;
using MigraDoc.DocumentObjectModel.Shapes;
using MigraDoc.Rendering;
using Section = MigraDoc.DocumentObjectModel.Section;
using Paragraph = MigraDoc.DocumentObjectModel.Paragraph;
using WpfBlock = System.Windows.Documents.Block;
using WpfParagraph = System.Windows.Documents.Paragraph;
using WpfSection = System.Windows.Documents.Section;
using WpfList = System.Windows.Documents.List;
using WpfInline = System.Windows.Documents.Inline;
using WpfRun = System.Windows.Documents.Run;
using WpfLineBreak = System.Windows.Documents.LineBreak;
using WpfSpan = System.Windows.Documents.Span;
using WpfHyperlink = System.Windows.Documents.Hyperlink;
using WpfTable = System.Windows.Documents.Table;
using WpfTableCell = System.Windows.Documents.TableCell;
using WpfTableRow = System.Windows.Documents.TableRow;
using MdElements = MigraDoc.DocumentObjectModel.DocumentElements;
using MdCell = MigraDoc.DocumentObjectModel.Tables.Cell;

namespace AA.Services;

/// <summary>
/// Exports a single HierarchyItem (Equipment / Task / Procedure / Vessel) to a fully
/// laid-out A4 PDF. MigraDoc handles word-wrap and pagination so text cannot clip or spill;
/// the hierarchy is rendered intact and relationships are grouped by tab.
/// </summary>
public static class PdfExporter
{
    static PdfExporter()
    {
        PdfSharp.Fonts.GlobalFontSettings.UseWindowsFontsUnderWindows = true;
        // Cache the set of fonts installed on this machine so we can quickly decide whether
        // a font requested by the rich-text editor is actually renderable. Anything not in
        // this set (e.g. WPF logical aliases like "Sans Serif") falls back to Calibri.
        _installedFonts = new HashSet<string>(
            System.Windows.Media.Fonts.SystemFontFamilies.Select(f => f.Source),
            StringComparer.OrdinalIgnoreCase);
    }

    private static readonly HashSet<string> _installedFonts;

    // WPF/CSS-style generic family aliases that PDFsharp cannot resolve directly.
    private static readonly Dictionary<string, string> _fontAliases = new(StringComparer.OrdinalIgnoreCase)
    {
        ["Sans Serif"] = "Arial",
        ["Sans-Serif"] = "Arial",
        ["SansSerif"] = "Arial",
        ["Serif"] = "Times New Roman",
        ["Monospace"] = "Consolas",
        ["Cursive"] = "Comic Sans MS",
        ["Fantasy"] = "Impact",
        ["system-ui"] = "Segoe UI",
    };

    /// <summary>Map a WPF font family name to one that PDFsharp can actually render.
    /// Falls back to Calibri (then Arial) if the requested font isn't installed.</summary>
    private static string ResolveFontName(string? requested)
    {
        if (string.IsNullOrWhiteSpace(requested)) return "Calibri";
        // FontFamily.Source can be a comma-separated fallback list ("Calibri, Arial").
        foreach (var raw in requested.Split(','))
        {
            var name = raw.Trim().Trim('\'', '"');
            if (name.Length == 0) continue;
            if (_fontAliases.TryGetValue(name, out var mapped)) name = mapped;
            if (_installedFonts.Contains(name)) return name;
        }
        if (_installedFonts.Contains("Calibri")) return "Calibri";
        if (_installedFonts.Contains("Arial")) return "Arial";
        return "Segoe UI";
    }

    public static void Export(HierarchyItem item, AppRepository repo, string path)
    {
        var doc = BuildDocument(item, repo);
        var renderer = new PdfDocumentRenderer { Document = doc };
        renderer.RenderDocument();
        renderer.PdfDocument.Save(path);
    }

    /// <summary>Export saved checklists to a nice A4 PDF. <paramref name="entries"/> is an ordered list
    /// of (optional group header, saved list); a group header is printed whenever the group changes.</summary>
    /// <param name="numbered">True for 1./2./3., false for bullets. No default on purpose: numbering
    /// asserts that the items run in sequence, which is a claim about the content, so the caller must
    /// have asked rather than inherited it.</param>
    public static void ExportSavedLists(string docTitle, IReadOnlyList<(string? Group, ChecklistTemplate Template)> entries, string path, bool numbered)
    {
        var doc = new Document();
        doc.Info.Title = docTitle;
        doc.Info.Author = "AA";
        DefineStyles(doc);

        var sec = doc.AddSection();
        sec.PageSetup.PageFormat = PageFormat.A4;
        sec.PageSetup.Orientation = Orientation.Portrait;
        sec.PageSetup.TopMargin = "2cm";
        sec.PageSetup.BottomMargin = "2cm";
        sec.PageSetup.LeftMargin = "2cm";
        sec.PageSetup.RightMargin = "2cm";
        sec.PageSetup.HeaderDistance = "1cm";
        sec.PageSetup.FooterDistance = "1cm";

        var hp = sec.Headers.Primary.AddParagraph();
        hp.Format.Font.Size = 9;
        hp.Format.Font.Color = new Color(120, 120, 120);
        hp.Format.TabStops.AddTabStop("16cm", TabAlignment.Right);
        hp.AddText($"Saved lists: {docTitle}");
        hp.AddTab();
        hp.AddText(DateTime.Now.ToString("yyyy-MM-dd HH:mm"));

        var fp = sec.Footers.Primary.AddParagraph();
        fp.Format.Alignment = ParagraphAlignment.Right;
        fp.Format.Font.Size = 9;
        fp.Format.Font.Color = new Color(120, 120, 120);
        fp.AddText("Page ");
        fp.AddPageField();
        fp.AddText(" / ");
        fp.AddNumPagesField();

        var titlePara = sec.AddParagraph();
        titlePara.Style = "Title";
        titlePara.AddText(docTitle);
        var sub = sec.AddParagraph();
        sub.Style = "Subtitle";
        sub.AddText($"Saved checklists  ·  {entries.Count} list{(entries.Count == 1 ? "" : "s")}");

        string? lastGroup = null;
        bool started = false;
        foreach (var (group, tpl) in entries)
        {
            var g = string.IsNullOrWhiteSpace(group) ? null : group;
            if (!started || g != lastGroup)
            {
                if (g != null) H1(sec, g);
                else if (started) H1(sec, "Ungrouped");
                lastGroup = g;
                started = true;
            }

            H2(sec, $"{(string.IsNullOrWhiteSpace(tpl.Name) ? "(unnamed list)" : tpl.Name)}   ({tpl.Items.Count} item{(tpl.Items.Count == 1 ? "" : "s")})");
            int n = 1;
            foreach (var it in tpl.Items)
            {
                var par = sec.AddParagraph();
                par.Style = "Bullet";
                par.AddFormattedText(numbered ? $"{n++}. " : "•  ", TextFormat.Bold);
                par.AddText(it.Title ?? "");
                var meta = new List<string>();
                if (it.IsJob) meta.Add("schedulable");
                if (meta.Count > 0)
                {
                    par.AddText("  ");
                    var m = par.AddFormattedText("(" + string.Join(", ", meta) + ")");
                    m.Color = new Color(120, 120, 120);
                    m.Italic = true;
                }
                WriteContainerBody(sec, it.Container, heading: "", leftIndent: "0.6cm");
                if (it.Container?.Files.Count > 0)
                {
                    var fpar = sec.AddParagraph();
                    fpar.Style = "Muted";
                    fpar.Format.LeftIndent = "0.6cm";
                    fpar.AddFormattedText("Files: ", TextFormat.Italic);
                    fpar.AddText(string.Join(", ", it.Container.Files.Select(f => f.Name)));
                }
            }
        }

        var renderer = new PdfDocumentRenderer { Document = doc };
        renderer.RenderDocument();
        renderer.PdfDocument.Save(path);
    }

    // ---------- document scaffolding ----------

    private static Document BuildDocument(HierarchyItem item, AppRepository repo)
    {
        var doc = new Document();
        doc.Info.Title = $"{item.Kind} - {item.Name}";
        doc.Info.Author = "AA";
        DefineStyles(doc);

        var sec = doc.AddSection();
        sec.PageSetup.PageFormat = PageFormat.A4;
        sec.PageSetup.Orientation = Orientation.Portrait;
        sec.PageSetup.TopMargin = "2cm";
        sec.PageSetup.BottomMargin = "2cm";
        sec.PageSetup.LeftMargin = "2cm";
        sec.PageSetup.RightMargin = "2cm";
        sec.PageSetup.HeaderDistance = "1cm";
        sec.PageSetup.FooterDistance = "1cm";

        var hp = sec.Headers.Primary.AddParagraph();
        hp.Format.Font.Size = 9;
        hp.Format.Font.Color = new Color(120, 120, 120);
        hp.Format.TabStops.AddTabStop("16cm", TabAlignment.Right);
        hp.AddText($"{KindLabel(item.Kind)}: {item.Name}");
        hp.AddTab();
        hp.AddText(DateTime.Now.ToString("yyyy-MM-dd HH:mm"));

        var fp = sec.Footers.Primary.AddParagraph();
        fp.Format.Alignment = ParagraphAlignment.Right;
        fp.Format.Font.Size = 9;
        fp.Format.Font.Color = new Color(120, 120, 120);
        fp.AddText("Page ");
        fp.AddPageField();
        fp.AddText(" / ");
        fp.AddNumPagesField();

        var titlePara = sec.AddParagraph();
        titlePara.Style = "Title";
        titlePara.AddText(item.Name);

        var sub = sec.AddParagraph();
        sub.Style = "Subtitle";
        sub.AddText(KindLabel(item.Kind));

        if (!string.IsNullOrWhiteSpace(item.Description))
        {
            var d = sec.AddParagraph();
            d.Style = "BodyItalic";
            d.AddText(item.Description);
        }

        // Body: notes -> specifics -> related items -> files
        WriteContainerBody(sec, item.Container, "Notes");
        WriteSpecifics(sec, item, repo);
        WriteRelationships(sec, item, repo);
        WriteFileBank(sec, item);

        return doc;
    }

    private static void DefineStyles(Document doc)
    {
        var normal = doc.Styles["Normal"]!;
        normal.Font.Name = ResolveFontName("Calibri");
        normal.Font.Size = 11;
        normal.ParagraphFormat.SpaceAfter = "3pt";
        normal.ParagraphFormat.LineSpacingRule = LineSpacingRule.Multiple;
        normal.ParagraphFormat.LineSpacing = 1.15;

        var title = doc.Styles.AddStyle("Title", "Normal");
        title.Font.Size = 26;
        title.Font.Bold = true;
        title.Font.Color = new Color(20, 20, 20);
        title.ParagraphFormat.SpaceAfter = "4pt";

        var subtitle = doc.Styles.AddStyle("Subtitle", "Normal");
        subtitle.Font.Size = 12;
        subtitle.Font.Color = new Color(120, 120, 120);
        subtitle.ParagraphFormat.SpaceAfter = "12pt";

        var h1 = doc.Styles.AddStyle("H1", "Normal");
        h1.Font.Size = 16;
        h1.Font.Bold = true;
        h1.ParagraphFormat.SpaceBefore = "16pt";
        h1.ParagraphFormat.SpaceAfter = "6pt";
        h1.ParagraphFormat.KeepWithNext = true;
        h1.ParagraphFormat.Borders.Bottom.Width = 0.75;
        h1.ParagraphFormat.Borders.Bottom.Color = new Color(60, 60, 60);

        var h2 = doc.Styles.AddStyle("H2", "Normal");
        h2.Font.Size = 13;
        h2.Font.Bold = true;
        h2.ParagraphFormat.SpaceBefore = "10pt";
        h2.ParagraphFormat.SpaceAfter = "4pt";
        h2.ParagraphFormat.KeepWithNext = true;

        var h3 = doc.Styles.AddStyle("H3", "Normal");
        h3.Font.Size = 11;
        h3.Font.Bold = true;
        h3.Font.Color = new Color(60, 60, 60);
        h3.ParagraphFormat.SpaceBefore = "6pt";
        h3.ParagraphFormat.SpaceAfter = "2pt";
        h3.ParagraphFormat.KeepWithNext = true;

        var bodyIt = doc.Styles.AddStyle("BodyItalic", "Normal");
        bodyIt.Font.Italic = true;
        bodyIt.Font.Color = new Color(80, 80, 80);

        var bullet = doc.Styles.AddStyle("Bullet", "Normal");
        bullet.ParagraphFormat.LeftIndent = "0.6cm";
        bullet.ParagraphFormat.FirstLineIndent = "-0.4cm";

        var muted = doc.Styles.AddStyle("Muted", "Normal");
        muted.Font.Color = new Color(120, 120, 120);
        muted.Font.Size = 10;
    }

    // ---------- specifics per kind ----------

    private static void WriteSpecifics(Section sec, HierarchyItem item, AppRepository repo)
    {
        switch (item)
        {
            case Equipment e: WriteEquipmentSpecifics(sec, e, repo); break;
            case TaskItem t: WriteTaskSpecifics(sec, t, repo); break;
            case Procedure p: WriteProcedureSpecifics(sec, p, repo); break;
        }
    }

    private static void WriteEquipmentSpecifics(Section sec, Equipment eq, AppRepository repo)
    {
        if (eq.Components.Count == 0 && eq.ProcedureIds.Count == 0 && eq.TaskIds.Count == 0) return;
        H1(sec, "Equipment/Area Details");

        if (eq.Components.Count > 0)
        {
            H2(sec, $"Components ({eq.Components.Count})");
            var tbl = sec.AddTable();
            tbl.Borders.Width = 0.5;
            tbl.Borders.Color = new Color(180, 180, 180);
            tbl.LeftPadding = "3pt"; tbl.RightPadding = "3pt"; tbl.TopPadding = "2pt"; tbl.BottomPadding = "2pt";
            tbl.AddColumn("5cm");
            tbl.AddColumn("11cm");
            var head = tbl.AddRow();
            head.Shading.Color = new Color(235, 235, 235);
            head.HeadingFormat = true;
            head.Cells[0].AddParagraph("Component").Format.Font.Bold = true;
            head.Cells[1].AddParagraph("Notes").Format.Font.Bold = true;
            foreach (var c in eq.Components)
            {
                var r = tbl.AddRow();
                r.Cells[0].AddParagraph(c.Name ?? "");
                r.Cells[1].AddParagraph(c.Notes ?? "");
            }
        }

        if (eq.ProcedureIds.Count > 0)
        {
            H2(sec, $"Linked Procedures ({eq.ProcedureIds.Count})");
            foreach (var id in eq.ProcedureIds)
            {
                if (repo.FindById(id) is not Procedure p) continue;
                H3(sec, p.Name);
                if (!string.IsNullOrWhiteSpace(p.Description)) Italic(sec, p.Description);
                if (p.Steps.Count > 0)
                {
                    int n = 1;
                    foreach (var s in p.Steps)
                    {
                        var line = $"{n++}. {(s.Done ? "[x]" : "[ ]")} {s.Title}";
                        var par = sec.AddParagraph(line);
                        par.Style = "Bullet";
                    }
                }
            }
        }

        if (eq.TaskIds.Count > 0)
        {
            H2(sec, $"Linked Tasks ({eq.TaskIds.Count})");
            foreach (var id in eq.TaskIds)
            {
                if (repo.FindById(id) is not TaskItem t) continue;
                WriteTaskSummary(sec, t);
            }
        }
    }

    /// <summary>Inline "when" meta for a task bullet: "10th–15th" style range when set, else "due &lt;date&gt;",
    /// or null when the task has no deadline.</summary>
    private static string? TaskWhen(TaskItem t)
    {
        if (!t.Deadline.HasValue) return null;
        return t.RangeStart.HasValue && t.RangeStart.Value.Date < t.Deadline.Value.Date
            ? $"{t.RangeStart.Value:yyyy-MM-dd} – {t.Deadline.Value:yyyy-MM-dd}"
            : $"due {t.Deadline.Value:yyyy-MM-dd}";
    }

    private static void WriteTaskSpecifics(Section sec, TaskItem t, AppRepository repo)
    {
        H1(sec, "Task Details");

        var tbl = sec.AddTable();
        tbl.Borders.Width = 0;
        tbl.AddColumn("4cm");
        tbl.AddColumn("12cm");
        if (t.RangeStart.HasValue && t.Deadline.HasValue && t.RangeStart.Value.Date < t.Deadline.Value.Date)
            AddKV(tbl, "Working range", $"{t.RangeStart.Value:yyyy-MM-dd} → {t.Deadline.Value:yyyy-MM-dd}");
        AddKV(tbl, "Deadline", t.Deadline?.ToString("yyyy-MM-dd") ?? "(none)");
        AddKV(tbl, "Recurrence", t.Recurrence.ToString());
        AddKV(tbl, "Status", t.IsComplete ? "Completed" : "Open");

        if (t.Subtasks.Count > 0)
        {
            H2(sec, $"Subtasks ({t.Subtasks.Count})");
            foreach (var st in t.Subtasks) WriteSubtaskDetailed(sec, st, depth: 1);
        }
    }

    /// <summary>Recursively render a subtask with its name, meta, description,
    /// rich-text notes (Container) and any nested subtasks. Indentation grows
    /// with depth so the hierarchy stays readable in the PDF.</summary>
    private static void WriteSubtaskDetailed(Section sec, TaskItem t, int depth)
    {
        var indent = $"{Math.Min(depth, 4) * 0.6:0.##}cm";

        var head = sec.AddParagraph();
        head.Format.LeftIndent = indent;
        head.Format.SpaceBefore = depth == 1 ? "6pt" : "3pt";
        head.Format.SpaceAfter = "2pt";
        head.Format.KeepWithNext = true;
        head.AddFormattedText(t.IsComplete ? "[x] " : "[ ] ", TextFormat.Bold);
        head.AddFormattedText(t.Name ?? "", TextFormat.Bold);
        var meta = new List<string>();
        if (TaskWhen(t) is string tw) meta.Add(tw);
        if (t.Recurrence != RecurrenceKind.None) meta.Add(t.Recurrence.ToString().ToLowerInvariant());
        if (meta.Count > 0)
        {
            head.AddText("  ");
            var muted = head.AddFormattedText("(" + string.Join(", ", meta) + ")");
            muted.Color = new Color(120, 120, 120);
            muted.Italic = true;
        }

        if (!string.IsNullOrWhiteSpace(t.Description))
        {
            var d = sec.AddParagraph(t.Description);
            d.Style = "Muted";
            d.Format.LeftIndent = indent;
        }

        // Per-subtask rich-text notes (Container body).
        WriteContainerBody(sec, t.Container, heading: "", leftIndent: indent);

        foreach (var child in t.Subtasks)
            WriteSubtaskDetailed(sec, child, depth + 1);
    }

    private static void WriteProcedureSpecifics(Section sec, Procedure p, AppRepository repo)
    {
        if (p.Steps.Count == 0) return;
        H1(sec, $"Checklist ({p.Steps.Count} step{(p.Steps.Count == 1 ? "" : "s")})");

        int n = 1;
        foreach (var s in p.Steps)
        {
            var head = sec.AddParagraph();
            head.Format.SpaceBefore = "6pt";
            head.Format.SpaceAfter = "2pt";
            head.Format.KeepWithNext = true;
            var ft = head.AddFormattedText($"{n++}. {(s.Done ? "[x]" : "[ ]")} ", TextFormat.Bold);
            ft.Color = s.Done ? new Color(0, 120, 0) : new Color(100, 100, 100);
            head.AddFormattedText(s.Title ?? "", TextFormat.Bold);
            if (s.Deadline.HasValue)
            {
                var due = head.AddFormattedText($"   (due {s.Deadline.Value:yyyy-MM-dd})", TextFormat.Italic);
                due.Color = new Color(100, 100, 100);
            }

            if (s.EquipmentIds.Count > 0)
            {
                var eqNames = s.EquipmentIds.Select(id => repo.FindById(id)?.Name).Where(x => x != null);
                var par = sec.AddParagraph();
                par.Style = "Muted";
                par.Format.LeftIndent = "0.6cm";
                par.AddFormattedText("Equipment/Area: ", TextFormat.Italic);
                par.AddText(string.Join(", ", eqNames!));
            }
            if (s.TaskIds.Count > 0)
            {
                var taskNames = s.TaskIds.Select(id => repo.FindById(id)?.Name).Where(x => x != null);
                var par = sec.AddParagraph();
                par.Style = "Muted";
                par.Format.LeftIndent = "0.6cm";
                par.AddFormattedText("Tasks: ", TextFormat.Italic);
                par.AddText(string.Join(", ", taskNames!));
            }

            // Per-step rich-text notes (container), indented under the step heading.
            WriteContainerBody(sec, s.Container, heading: "", leftIndent: "0.6cm");
        }
    }

    private static void WriteTaskSummary(Section sec, TaskItem t)
    {
        var par = sec.AddParagraph();
        par.Style = "Bullet";
        par.AddFormattedText($"{(t.IsComplete ? "[x] " : "[ ] ")}", TextFormat.Bold);
        par.AddFormattedText(t.Name, TextFormat.Bold);
        var meta = new List<string>();
        if (TaskWhen(t) is string tw) meta.Add(tw);
        if (t.Recurrence != RecurrenceKind.None) meta.Add(t.Recurrence.ToString().ToLowerInvariant());
        if (meta.Count > 0)
        {
            par.AddText("  ");
            var muted = par.AddFormattedText("(" + string.Join(", ", meta) + ")");
            muted.Color = new Color(120, 120, 120);
            muted.Italic = true;
        }
        if (!string.IsNullOrWhiteSpace(t.Description))
        {
            var d = sec.AddParagraph(t.Description);
            d.Style = "Muted";
            d.Format.LeftIndent = "0.6cm";
        }
    }

    // ---------- relationships ----------

    private static void WriteRelationships(Section sec, HierarchyItem item, AppRepository repo)
    {
        var related = repo.RelatedItems(item).Distinct().ToList();
        if (related.Count == 0) return;

        H1(sec, $"Relationships ({related.Count})");
        var p0 = sec.AddParagraph();
        p0.Style = "BodyItalic";
        p0.AddText("Items linked to this one, grouped by tab.");

        foreach (var kind in new[] { ItemKind.Equipment, ItemKind.Task, ItemKind.Procedure, ItemKind.Vessel })
        {
            var grp = related.Where(r => r.Kind == kind)
                             .OrderBy(r => r.Name, StringComparer.OrdinalIgnoreCase)
                             .ToList();
            if (grp.Count == 0) continue;

            H2(sec, $"{KindLabel(kind)} ({grp.Count})");
            foreach (var r in grp)
            {
                var line = sec.AddParagraph();
                line.Style = "Bullet";
                line.AddFormattedText(r.Name, TextFormat.Bold);
                if (!string.IsNullOrWhiteSpace(r.Description))
                {
                    line.AddText(" — ");
                    line.AddText(Shorten(r.Description, 180));
                }
            }
        }
    }

    // ---------- file bank ----------

    private static void WriteFileBank(Section sec, HierarchyItem item)
    {
        var files = item.Container?.Files;
        if (files == null || files.Count == 0) return;
        H1(sec, $"Attached Files ({files.Count})");
        var tbl = sec.AddTable();
        tbl.Borders.Width = 0.5;
        tbl.Borders.Color = new Color(200, 200, 200);
        tbl.LeftPadding = "3pt"; tbl.RightPadding = "3pt"; tbl.TopPadding = "2pt"; tbl.BottomPadding = "2pt";
        tbl.AddColumn("5cm");
        tbl.AddColumn("2cm");
        tbl.AddColumn("9cm");
        var head = tbl.AddRow();
        head.Shading.Color = new Color(235, 235, 235);
        head.HeadingFormat = true;
        head.Cells[0].AddParagraph("Name").Format.Font.Bold = true;
        head.Cells[1].AddParagraph("Kind").Format.Font.Bold = true;
        head.Cells[2].AddParagraph("Path / Link").Format.Font.Bold = true;
        foreach (var f in files)
        {
            var r = tbl.AddRow();
            r.Cells[0].AddParagraph(f.Name ?? "");
            r.Cells[1].AddParagraph(f.Kind.ToString());
            var pp = r.Cells[2].AddParagraph(f.Path ?? "");
            pp.Format.Font.Size = 9;
        }
    }

    // ---------- container rich text ----------

    private static void WriteContainerBody(Section sec, Container? c, string heading, string? leftIndent = null)
    {
        if (c == null || string.IsNullOrWhiteSpace(c.RichTextXaml)) return;
        FlowDocument? fd = null;
        try
        {
            // The editor saves rich text via TextRange.Save(DataFormats.Xaml), which produces
            // a <Section> root rather than a <FlowDocument>. Round-trip through TextRange.Load
            // into an empty FlowDocument so all of WPF's variants (Section, FlowDocument, Span,
            // raw runs) are parsed reliably; XamlReader.Load only succeeds for a FlowDocument root.
            fd = new FlowDocument();
            var range = new TextRange(fd.ContentStart, fd.ContentEnd);
            using var ms = new MemoryStream(Encoding.UTF8.GetBytes(c.RichTextXaml));
            range.Load(ms, System.Windows.DataFormats.Xaml);
        }
        catch
        {
            fd = null;
        }

        var firstNewIndex = sec.Elements.Count;

        if (fd == null)
        {
            // Last-ditch fallback: never dump raw XAML tags into the PDF. Strip everything
            // between angle brackets and decode the few entities the editor emits.
            var plain = StripXamlTags(c.RichTextXaml);
            if (string.IsNullOrWhiteSpace(plain)) return;
            if (!string.IsNullOrEmpty(heading)) H1(sec, heading);
            foreach (var line in plain.Replace("\r\n", "\n").Split('\n'))
            {
                if (string.IsNullOrWhiteSpace(line)) continue;
                sec.AddParagraph(line);
            }
        }
        else
        {
            // Skip section entirely if document has no visible text.
            var textPeek = new TextRange(fd.ContentStart, fd.ContentEnd).Text;
            if (string.IsNullOrWhiteSpace(textPeek)) return;

            if (!string.IsNullOrEmpty(heading)) H1(sec, heading);
            foreach (var block in fd.Blocks) RenderBlock(sec.Elements, block);
        }

        // When rendered under a subtask, push everything to the requested indent
        // so the notes visually belong to the parent subtask in the PDF. Add to any
        // indent the paragraph already carries from the rich text so relative
        // indentation (e.g. nested bullets) survives.
        if (!string.IsNullOrEmpty(leftIndent))
        {
            var baseCm = ParseLengthCm(leftIndent);
            for (int i = firstNewIndex; i < sec.Elements.Count; i++)
            {
                if (sec.Elements[i] is MigraDoc.DocumentObjectModel.Paragraph mp)
                {
                    var existing = mp.Format.LeftIndent.Centimeter;
                    mp.Format.LeftIndent = Unit.FromCentimeter(baseCm + existing);
                }
            }
        }
    }

    private static double ParseLengthCm(string s)
    {
        try { return Unit.Parse(s).Centimeter; } catch { return 0; }
    }

    private static string StripXamlTags(string xaml)
    {
        if (string.IsNullOrEmpty(xaml)) return string.Empty;
        var sb = new StringBuilder(xaml.Length);
        bool inTag = false;
        foreach (var ch in xaml)
        {
            if (ch == '<') { inTag = true; continue; }
            if (ch == '>') { inTag = false; sb.Append(' '); continue; }
            if (!inTag) sb.Append(ch);
        }
        return System.Net.WebUtility.HtmlDecode(sb.ToString()).Trim();
    }

    private static void RenderBlock(MdElements target, WpfBlock block, double listLevelCm = 0)
    {
        switch (block)
        {
            case WpfParagraph p:
                {
                    var par = target.AddParagraph();
                    ApplyParagraphFormat(par, p);
                    // Whole-line highlight: MigraDoc can't shade a sub-run span, but if every run in the
                    // paragraph shares one background we can shade the paragraph (the common "highlight
                    // this line" case). Partial (a few words) highlights aren't representable in MigraDoc.
                    if (UniformInlineBackground(p) is Color hi) par.Format.Shading.Color = hi;
                    var anyText = false;
                    foreach (var inline in p.Inlines) anyText |= RenderInline(par, inline);
                    if (!anyText) par.AddText(" ");
                    break;
                }
            case WpfList list:
                {
                    int idx = 1;
                    var numbered = list.MarkerStyle != System.Windows.TextMarkerStyle.None
                                   && list.MarkerStyle != System.Windows.TextMarkerStyle.Disc
                                   && list.MarkerStyle != System.Windows.TextMarkerStyle.Box
                                   && list.MarkerStyle != System.Windows.TextMarkerStyle.Circle
                                   && list.MarkerStyle != System.Windows.TextMarkerStyle.Square;
                    // Each nesting level adds 0.6 cm so deeper bullets/numbers indent further,
                    // exactly mirroring the visual nesting in the WPF editor.
                    double levelLeftCm = 0.6 + listLevelCm;
                    foreach (var li in list.ListItems)
                    {
                        foreach (var b in li.Blocks)
                        {
                            if (b is WpfParagraph lp)
                            {
                                var par = target.AddParagraph();
                                ApplyParagraphFormat(par, lp);
                                // Position the bullet/number at this nesting level with a hanging
                                // indent so wrapped lines align under the text, not the marker.
                                par.Format.LeftIndent = Unit.FromCentimeter(levelLeftCm);
                                par.Format.FirstLineIndent = Unit.FromCentimeter(-0.4);
                                par.AddText(numbered ? $"{idx++}. " : "\u2022 ");
                                foreach (var inline in lp.Inlines) RenderInline(par, inline);
                            }
                            else if (b is WpfList nested)
                            {
                                RenderBlock(target, nested, listLevelCm + 0.6);
                            }
                            else RenderBlock(target, b, listLevelCm);
                        }
                    }
                    break;
                }
            case WpfTable table:
                RenderTable(target, table);
                break;
            case WpfSection s:
                foreach (var b in s.Blocks) RenderBlock(target, b, listLevelCm);
                break;
        }
    }

    // ---------- tables (Insert-table in the editor -> a real MigraDoc table, not dropped) ----------

    private static void RenderTable(MdElements target, WpfTable wt)
    {
        var rows = wt.RowGroups.SelectMany(g => g.Rows).ToList();
        if (rows.Count == 0) return;
        // True column count must account for row-spans carried down from earlier rows (a rowspan that is
        // NOT in the widest row would otherwise be under-counted, dropping a real cell). Simulate placement.
        int colCount = Math.Max(wt.Columns.Count, TrueColumnCount(rows));
        if (colCount < 1) colCount = 1;

        var mt = target.AddTable();
        mt.Borders.Visible = false;               // borders are applied per-cell, mirroring the editor
        var widths = ComputeColumnWidthsCm(wt, colCount, 16.0);
        for (int c = 0; c < colCount; c++) mt.AddColumn(Unit.FromCentimeter(widths[c]));
        for (int r = 0; r < rows.Count; r++) mt.AddRow();

        // Track cells covered by a row/column span so real cells land in the right column.
        var occupied = new bool[rows.Count, colCount];
        for (int r = 0; r < rows.Count; r++)
        {
            int col = 0;
            foreach (var wc in rows[r].Cells)
            {
                while (col < colCount && occupied[r, col]) col++;
                if (col >= colCount) break;
                int cs = Math.Clamp(Math.Max(1, wc.ColumnSpan), 1, colCount - col);
                int rs = Math.Clamp(Math.Max(1, wc.RowSpan), 1, rows.Count - r);

                var mcell = mt.Rows[r].Cells[col];
                if (cs > 1) mcell.MergeRight = cs - 1;
                if (rs > 1) mcell.MergeDown = rs - 1;
                ApplyCellBorders(mcell, wc);
                if (TryGetColor(wc.Background, out var bg)) mcell.Shading.Color = bg;
                if (wc.FontWeight.ToOpenTypeWeight() >= 600) mcell.Format.Font.Bold = true;  // header row
                RenderCellContent(mcell, wc);

                for (int dr = 0; dr < rs; dr++)
                    for (int dc = 0; dc < cs; dc++)
                        occupied[r + dr, col + dc] = true;
                col += cs;
            }
        }
    }

    /// <summary>How many columns the table truly needs — simulates cell placement with an unbounded grid
    /// (skipping cells still covered by a row-span from an earlier row) and returns the furthest column
    /// reached. Prevents dropping a cell when a row-span lives outside the widest row (pasted tables).</summary>
    private static int TrueColumnCount(List<WpfTableRow> rows)
    {
        var occupied = new HashSet<(int r, int c)>();
        int maxCol = 0;
        for (int r = 0; r < rows.Count; r++)
        {
            int col = 0;
            foreach (var wc in rows[r].Cells)
            {
                while (occupied.Contains((r, col))) col++;
                int cs = Math.Max(1, wc.ColumnSpan);
                int rs = Math.Max(1, wc.RowSpan);
                for (int dr = 0; dr < rs; dr++)
                    for (int dc = 0; dc < cs; dc++)
                        occupied.Add((r + dr, col + dc));
                col += cs;
                if (col > maxCol) maxCol = col;
            }
        }
        return maxCol;
    }

    private static void RenderCellContent(MdCell mcell, WpfTableCell wc)
    {
        int before = mcell.Elements.Count;
        foreach (var b in wc.Blocks) RenderBlock(mcell.Elements, b);
        if (mcell.Elements.Count == before) mcell.AddParagraph();   // keep empty cells non-collapsed
    }

    private static void ApplyCellBorders(MdCell mcell, WpfTableCell wc)
    {
        var th = wc.BorderThickness;
        double w = Math.Max(Math.Max(th.Left, th.Right), Math.Max(th.Top, th.Bottom));
        if (w <= 0) { mcell.Borders.Visible = false; return; }
        mcell.Borders.Width = w;
        mcell.Borders.Color = TryGetColor(wc.BorderBrush, out var bc) ? bc : new Color(120, 120, 120);
    }

    /// <summary>Column widths in cm: honour explicit absolute (px) widths, otherwise split the printable
    /// width (~16 cm) evenly \u2014 which is how the editor's auto-width columns look.</summary>
    private static double[] ComputeColumnWidthsCm(WpfTable wt, int colCount, double totalCm)
    {
        const double pxToCm = 2.54 / 96.0;
        var w = new double[colCount];
        bool anyAbsolute = false;
        for (int c = 0; c < colCount && c < wt.Columns.Count; c++)
        {
            var gl = wt.Columns[c].Width;
            if (gl.IsAbsolute && gl.Value > 0) { w[c] = gl.Value * pxToCm; anyAbsolute = true; }
        }
        if (!anyAbsolute)
        {
            for (int c = 0; c < colCount; c++) w[c] = totalCm / colCount;
            return w;
        }
        double known = w.Where(x => x > 0).Sum();
        int missing = w.Count(x => x <= 0);
        double each = missing > 0 ? Math.Max(1.0, (totalCm - known) / missing) : 0;
        for (int c = 0; c < colCount; c++) if (w[c] <= 0) w[c] = each;
        double tot = w.Sum();
        if (tot > totalCm) { double k = totalCm / tot; for (int c = 0; c < colCount; c++) w[c] *= k; }
        return w;
    }

    private static void ApplyParagraphFormat(Paragraph par, WpfParagraph wp)
    {
        par.Format.Alignment = wp.TextAlignment switch
        {
            System.Windows.TextAlignment.Center => ParagraphAlignment.Center,
            System.Windows.TextAlignment.Right => ParagraphAlignment.Right,
            System.Windows.TextAlignment.Justify => ParagraphAlignment.Justify,
            _ => ParagraphAlignment.Left,
        };
        if (TryGetColor(wp.Background, out var bg))
            par.Format.Shading.Color = bg;

        // Carry WPF indentation across to MigraDoc so indented paragraphs in the rich-text
        // notes keep their visual structure in the exported PDF (1 px = 1/96 in = 0.02646 cm).
        // WPF's Indent/Outdent buttons may record the shift on Margin.Left OR on TextIndent
        // depending on the run; treat a POSITIVE TextIndent as a whole-paragraph indent
        // (matching what the user sees in the editor) and a NEGATIVE TextIndent as a hanging
        // first-line indent. Summing Margin.Left with positive TextIndent is correct either way:
        // whichever one carries the indent contributes, and they aren't both set by the buttons.
        const double pxToCm = 2.54 / 96.0;
        double leftCm = wp.Margin.Left > 0 ? wp.Margin.Left * pxToCm : 0;
        double firstLineCm = 0;
        if (wp.TextIndent > 0) leftCm += wp.TextIndent * pxToCm;
        else if (wp.TextIndent < 0) firstLineCm = wp.TextIndent * pxToCm;
        if (leftCm > 0) par.Format.LeftIndent = Unit.FromCentimeter(leftCm);
        if (firstLineCm != 0) par.Format.FirstLineIndent = Unit.FromCentimeter(firstLineCm);
        if (wp.Margin.Right > 0)
            par.Format.RightIndent = Unit.FromCentimeter(wp.Margin.Right * pxToCm);
    }

    private static bool RenderInline(Paragraph par, WpfInline inline)
    {
        switch (inline)
        {
            case WpfRun run:
                if (string.IsNullOrEmpty(run.Text)) return false;
                // Plain runs may contain bare URLs / e-mail addresses the user just typed or pasted as
                // text — turn those into real clickable PDF links too, not only formal Hyperlink elements.
                return AddRunAutoLinked(par, run);
            case WpfLineBreak:
                par.AddLineBreak();
                return true;
            case WpfHyperlink hl:
                {
                    var uri = NormalizeLinkUri(hl.NavigateUri?.ToString());
                    if (uri == null)
                    {
                        // No explicit target: render the display text as ordinary runs so auto-linking wires
                        // up only a URL substring (if any) rather than making the whole label clickable.
                        var plain = false;
                        foreach (var child in hl.Inlines) plain |= RenderInline(par, child);
                        return plain;
                    }
                    // A real target: the whole display text is the clickable link.
                    var link = par.AddHyperlink(uri, HyperlinkType.Web);
                    var any = false;
                    foreach (var child in hl.Inlines)
                    {
                        if (child is WpfRun lr && !string.IsNullOrEmpty(lr.Text)) { AddLinkedText(link, lr, lr.Text); any = true; }
                        else any |= RenderInline(par, child);
                    }
                    return any;
                }
            case WpfSpan span:
                {
                    var any = false;
                    foreach (var child in span.Inlines) any |= RenderInline(par, child);
                    return any;
                }
        }
        return false;
    }

    private static void AddRun(Paragraph par, WpfInline source, string text)
    {
        var ft = par.AddFormattedText(ApplyStrike(source, text), ResolveFormat(source));
        if (TryGetColor(source.Foreground, out var fg)) ft.Color = fg;
        if (source.FontFamily != null && !string.IsNullOrEmpty(source.FontFamily.Source))
            ft.Font.Name = ResolveFontName(source.FontFamily.Source);
        if (source.FontSize > 0)
            ft.Font.Size = source.FontSize * 0.75; // WPF px -> pt
    }

    // ---------- clickable links (formal Hyperlinks + auto-detected URLs / e-mails) ----------

    private static readonly Color LinkBlue = new Color(11, 97, 164);

    // URL (http/https/www.) or e-mail address. Deliberately conservative:
    //  * a start-of-token lookbehind means `www.`/`http`/an address only match at the START of a token,
    //    so mid-token text like `backup_www.tar.gz` or `C:\svc\www.cache\x` is NOT mis-linked — and it
    //    also keeps matching linear (non-boundary positions fail in O(1), so a long unbroken paste can't
    //    drive the local-part scan quadratically);
    //  * the atomic local part and non-overlapping domain labels remove backtracking from the mail branch.
    private static readonly System.Text.RegularExpressions.Regex LinkRegex = new(
        @"(?<=^|[\s(\[<""'])(?:(?<url>(?:https?://|www\.)[^\s<>()]+)|(?<mail>(?>[A-Za-z0-9._%+\-]+)@[A-Za-z0-9\-]+(?:\.[A-Za-z0-9\-]+)*\.[A-Za-z]{2,}))",
        System.Text.RegularExpressions.RegexOptions.Compiled | System.Text.RegularExpressions.RegexOptions.IgnoreCase);

    /// <summary>Render a plain run, promoting any bare URL / e-mail it contains into a clickable link
    /// while keeping the surrounding text (and the run's own formatting) intact.</summary>
    private static bool AddRunAutoLinked(Paragraph par, WpfRun run)
    {
        var text = run.Text;
        bool any = false;
        foreach (var (seg, uri) in ScanLinks(text))
        {
            if (seg.Length == 0) continue;
            if (uri != null) AddLinkedText(par.AddHyperlink(uri, HyperlinkType.Web), run, seg);
            else AddRun(par, run, seg);
            any = true;
        }
        return any;
    }

    /// <summary>Add link text to a MigraDoc hyperlink, carrying the source run's font/size but forcing the
    /// familiar blue-underlined link look so it reads as a link on the page as well as being clickable.</summary>
    private static void AddLinkedText(MigraDoc.DocumentObjectModel.Hyperlink link, WpfInline source, string text)
    {
        var ft = link.AddFormattedText(ApplyStrike(source, text), ResolveFormat(source) | TextFormat.Underline);
        ft.Color = LinkBlue;
        if (source.FontFamily != null && !string.IsNullOrEmpty(source.FontFamily.Source))
            ft.Font.Name = ResolveFontName(source.FontFamily.Source);
        if (source.FontSize > 0)
            ft.Font.Size = source.FontSize * 0.75;
    }

    /// <summary>Split text into alternating (text, uri) segments. A non-null uri marks a clickable link;
    /// trailing sentence punctuation is pushed back into the following plain-text segment.</summary>
    private static IEnumerable<(string text, string? uri)> ScanLinks(string text)
    {
        if (string.IsNullOrEmpty(text)) yield break;
        int last = 0;
        foreach (System.Text.RegularExpressions.Match m in LinkRegex.Matches(text))
        {
            var raw = m.Value;
            int len = raw.Length;
            while (len > 0 && ".,;:!?)]}'\"".IndexOf(raw[len - 1]) >= 0) len--;   // trim trailing punctuation
            if (len == 0) continue;
            var linkText = raw.Substring(0, len);
            if (m.Index > last) yield return (text.Substring(last, m.Index - last), null);
            yield return (linkText, ToUri(linkText, m.Groups["mail"].Success));
            last = m.Index + len;
        }
        if (last < text.Length) yield return (text.Substring(last), null);
    }

    private static string ToUri(string linkText, bool isMail) =>
        isMail ? "mailto:" + linkText
        : linkText.StartsWith("www.", StringComparison.OrdinalIgnoreCase) ? "https://" + linkText
        : linkText;

    /// <summary>Normalise a formal hyperlink's target (add a scheme to a bare www. host); null when empty.</summary>
    private static string? NormalizeLinkUri(string? uri)
    {
        if (string.IsNullOrWhiteSpace(uri)) return null;
        uri = uri.Trim();
        return uri.StartsWith("www.", StringComparison.OrdinalIgnoreCase) ? "https://" + uri : uri;
    }

    private static TextFormat ResolveFormat(WpfInline source)
    {
        var format = TextFormat.NotBold;
        if (source.FontWeight.ToOpenTypeWeight() >= 600) format |= TextFormat.Bold;
        if (source.FontStyle == System.Windows.FontStyles.Italic || source.FontStyle == System.Windows.FontStyles.Oblique)
            format |= TextFormat.Italic;
        // Real underline only — strikethrough is rendered in the text itself (see ApplyStrike), because
        // MigraDoc has no strikethrough flag and rendering it as underline would be misleading.
        if (HasDecoration(source, System.Windows.TextDecorationLocation.Underline))
            format |= TextFormat.Underline;
        return format;
    }

    private static bool HasDecoration(WpfInline s, System.Windows.TextDecorationLocation loc) =>
        s.TextDecorations != null && s.TextDecorations.Any(d => d.Location == loc);

    // MigraDoc/PDFsharp has no strikethrough font flag, so struck text gets the Unicode combining
    // long-stroke overlay (U+0336) after each character — a genuine line through the glyphs that stays
    // selectable — instead of the old, misleading fallback to underline.
    private const char CombiningStrikeChar = '̶';   // combining long stroke overlay
    private static string ApplyStrike(WpfInline source, string text)
    {
        if (string.IsNullOrEmpty(text) || !HasDecoration(source, System.Windows.TextDecorationLocation.Strikethrough))
            return text;
        var sb = new StringBuilder(text.Length * 2);
        for (int i = 0; i < text.Length;)
        {
            // Advance a full code point so the combining overlay never lands inside a surrogate pair (emoji).
            int n = char.IsHighSurrogate(text[i]) && i + 1 < text.Length && char.IsLowSurrogate(text[i + 1]) ? 2 : 1;
            sb.Append(text, i, n);
            // Strike glyphs only, not whitespace: a combining mark on a space produces a stray stroke at a
            // soft-wrap boundary (the mark stays attached to the space that moves to the next line).
            if (!char.IsControl(text[i]) && !char.IsWhiteSpace(text[i])) sb.Append(CombiningStrikeChar);
            i += n;
        }
        return sb.ToString();
    }

    /// <summary>If every text run in the paragraph shares one non-transparent background, return it (so the
    /// whole paragraph can be shaded); null when backgrounds are mixed/absent.</summary>
    private static Color? UniformInlineBackground(WpfParagraph p)
    {
        Color? found = null;
        bool anyText = false;
        foreach (var run in EnumRuns(p.Inlines))
        {
            if (string.IsNullOrEmpty(run.Text)) continue;
            anyText = true;
            if (!TryGetColor(EffectiveBackground(run), out var c)) return null;
            if (found == null) found = c;
            else if (!found.Value.Equals(c)) return null;
        }
        if (!anyText || found is not Color fc) return null;
        // The edit-lock marks protected text with a pale-gold background sentinel — don't leak that
        // internal marker into the PDF as a highlight.
        if (fc.R == 255 && fc.G == 230 && fc.B == 153) return null;
        return fc;
    }

    private static IEnumerable<WpfRun> EnumRuns(System.Windows.Documents.InlineCollection inlines)
    {
        foreach (var il in inlines)
        {
            if (il is WpfRun r) yield return r;
            else if (il is WpfSpan sp) foreach (var x in EnumRuns(sp.Inlines)) yield return x; // Hyperlink : Span
        }
    }

    /// <summary>A run's effective highlight: its own background, else the nearest ancestor's (WPF paints a
    /// span's/paragraph's background behind its text even though Background isn't an inherited property).</summary>
    private static System.Windows.Media.Brush? EffectiveBackground(System.Windows.Documents.TextElement te)
    {
        System.Windows.DependencyObject? d = te;
        while (d is System.Windows.Documents.TextElement t)
        {
            if (t.Background != null) return t.Background;
            if (t is WpfParagraph) break;   // stop at the paragraph — don't inherit a table cell/row background
            d = t.Parent;
        }
        return null;
    }

    private static bool TryGetColor(System.Windows.Media.Brush? brush, out Color color)
    {
        if (brush is System.Windows.Media.SolidColorBrush sb)
        {
            var c = sb.Color;
            // Treat fully-transparent or "default" white-on-dark theme brushes as no override.
            if (c.A == 0) { color = default; return false; }
            color = new Color(c.R, c.G, c.B);
            return true;
        }
        color = default;
        return false;
    }

    // ---------- helpers ----------

    private static void H1(Section sec, string text) { var p = sec.AddParagraph(text); p.Style = "H1"; }
    private static void H2(Section sec, string text) { var p = sec.AddParagraph(text); p.Style = "H2"; }
    private static void H3(Section sec, string text) { var p = sec.AddParagraph(text); p.Style = "H3"; }
    private static void Italic(Section sec, string text) { var p = sec.AddParagraph(text); p.Style = "BodyItalic"; }

    private static string KindLabel(ItemKind k) => k switch
    {
        ItemKind.Equipment => "Equipment/Area",
        _ => k.ToString()
    };

    private static void AddKV(MigraDoc.DocumentObjectModel.Tables.Table tbl, string key, string value)
    {
        var r = tbl.AddRow();
        var kp = r.Cells[0].AddParagraph(key);
        kp.Format.Font.Bold = true;
        kp.Format.Font.Color = new Color(80, 80, 80);
        r.Cells[1].AddParagraph(value);
    }

    private static string Shorten(string s, int max)
    {
        s = s.Replace('\r', ' ').Replace('\n', ' ').Trim();
        if (s.Length <= max) return s;
        return s.Substring(0, max - 1) + "…";
    }
}
