using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using System.Windows;
using System.Windows.Documents;
using System.Windows.Media;

namespace AA.Sire;

/// <summary>Renders a SIRE question into a WPF <see cref="FlowDocument"/> that matches the original SIRE
/// Knowledge Bank styling — Segoe UI 13, PDF bullets preserved as nested lists, and the colour-coded
/// section headers (amber Inspector Actions, green Expected Evidence, red Negative-Observation Grounds).
/// The same document is shown in the SIRE tab's detail pane AND serialized (via TextRange, AA's own
/// rich-text format) into the container body on quick-add, so an imported item keeps the formatting.</summary>
public static class SireFlow
{
    private static readonly FontFamily Segoe = new("Segoe UI");

    private static Brush B(string hex)
    {
        var b = new SolidColorBrush((Color)ColorConverter.ConvertFromString(hex));
        b.Freeze();
        return b;
    }

    private static readonly Brush Primary = B("#1E40AF");
    private static readonly Brush Muted = B("#64748B");
    private static readonly Brush Slate = B("#334155");
    private static readonly Brush ChipBg = B("#F8FAFC");

    private readonly record struct Scheme(Brush Bg, Brush Fg);
    private static readonly Scheme Default = new(B("#F1F5F9"), B("#475569"));
    private static readonly Scheme Amber = new(B("#FEF3C7"), B("#92400E"));
    private static readonly Scheme Green = new(B("#DCFCE7"), B("#166534"));
    private static readonly Scheme Red = new(B("#FEE2E2"), B("#991B1B"));

    /// <summary>Build the question detail document. <paramref name="bodyBrush"/> colours the flowing body
    /// text (pass AA's theme foreground for the on-screen pane, or a fixed dark for the container editor).</summary>
    public static FlowDocument BuildQuestion(SireQuestion q, Brush? bodyBrush = null)
    {
        var doc = NewDoc(bodyBrush);
        doc.Blocks.Add(Heading($"Q {q.QuestionNumber}", 20, Primary));
        doc.Blocks.Add(Line($"{q.ChapterDisplay}   ·   Section {q.Section}   ·   {q.QuestionTypeDisplay}", 11, Muted, italic: true));
        if (!string.IsNullOrWhiteSpace(q.ShortQuestionText))
            doc.Blocks.Add(Heading(q.ShortQuestionText, 15, Slate));
        if (!string.IsNullOrWhiteSpace(q.FullQuestionText))
            doc.Blocks.Add(Chip(q.FullQuestionText, ChipBg, Slate));
        var meta = $"Vessel: {q.VesselTypesDisplay}" + (string.IsNullOrWhiteSpace(q.RoviqSequence) ? "" : $"      ROVIQ: {q.RoviqSequence}");
        doc.Blocks.Add(Line(meta, 11, Primary));

        AddSection(doc, "DATA SOURCE", q.DataSource, Default);
        AddSection(doc, "PUBLICATIONS", q.Publications, Default);
        AddSection(doc, "OBJECTIVE", q.Objective, Default);
        AddSection(doc, "INDUSTRY GUIDANCE", q.IndustryGuidance, Default);
        AddSection(doc, "INSPECTION GUIDANCE", q.InspectionGuidance, Default);
        AddSection(doc, "SUGGESTED INSPECTOR ACTIONS", q.SuggestedInspectorActions, Amber);
        AddSection(doc, "EXPECTED EVIDENCE", q.ExpectedEvidence, Green);
        AddSection(doc, "POTENTIAL GROUNDS FOR A NEGATIVE OBSERVATION", q.PotentialNegativeObservationGrounds, Red);

        if (q.EvidenceTags.Count > 0)
            doc.Blocks.Add(Line("Smart tags: " + string.Join("   ·   ", q.EvidenceTags), 10, Muted));
        return doc;
    }

    /// <summary>Overview document for a section/chapter parent (title + the list of its questions).</summary>
    public static FlowDocument BuildOverview(string title, IReadOnlyList<SireQuestion> qs, Brush? bodyBrush = null)
    {
        var doc = NewDoc(bodyBrush);
        doc.Blocks.Add(Heading(title, 18, Primary));
        doc.Blocks.Add(Line($"{qs.Count} SIRE 2.0 question(s). Imported from the SIRE 2.0 Knowledge Bank.", 11, Muted, italic: true));
        var list = new List { MarkerStyle = TextMarkerStyle.Disc, Margin = new Thickness(0, 4, 0, 0) };
        foreach (var q in qs)
            list.ListItems.Add(new ListItem(new Paragraph(new Run($"Q {q.QuestionNumber} — {q.ShortQuestionText}")) { Margin = new Thickness(0, 1, 0, 1) }));
        doc.Blocks.Add(list);
        return doc;
    }

    /// <summary>Serialize a document to AA's container rich-text format (what <c>TextRange.Save</c> with
    /// DataFormats.Xaml produces — a Section root that AA's editor/viewer load back verbatim).</summary>
    public static string ToContainerXaml(FlowDocument doc)
    {
        var range = new TextRange(doc.ContentStart, doc.ContentEnd);
        using var ms = new MemoryStream();
        range.Save(ms, DataFormats.Xaml);
        return Encoding.UTF8.GetString(ms.ToArray());
    }

    // ---------- building blocks ----------

    private static FlowDocument NewDoc(Brush? bodyBrush) => new()
    {
        FontFamily = Segoe,
        FontSize = 13,
        PagePadding = new Thickness(0),
        Foreground = bodyBrush ?? Slate
    };

    // All text is normal weight (no bold) — hierarchy comes from size, colour, the chip backgrounds and
    // the ALL-CAPS section labels, so the body reads cleanly and stays easy to edit.
    private static Paragraph Heading(string text, double size, Brush fg)
        => new(new Run(text) { Foreground = fg }) { FontSize = size, Margin = new Thickness(0, 0, 0, 4) };

    private static Paragraph Line(string text, double size, Brush fg, bool italic = false)
        => new(new Run(text) { Foreground = fg }) { FontSize = size, FontStyle = italic ? FontStyles.Italic : FontStyles.Normal, Margin = new Thickness(0, 0, 0, 6) };

    private static Paragraph Chip(string text, Brush bg, Brush fg)
        => new(new Run(text) { Foreground = fg }) { Background = bg, Padding = new Thickness(10, 8, 10, 8), Margin = new Thickness(0, 2, 0, 8) };

    private static void AddSection(FlowDocument doc, string label, string? body, Scheme scheme)
    {
        if (string.IsNullOrWhiteSpace(body)) return;
        doc.Blocks.Add(new Paragraph(new Run(label) { Foreground = scheme.Fg })
        {
            Background = scheme.Bg,
            FontSize = 12,
            Padding = new Thickness(8, 4, 8, 4),
            Margin = new Thickness(0, 10, 0, 4)
        });
        foreach (var block in ParseBlocks(body)) doc.Blocks.Add(block);
    }

    /// <summary>Parse a body string into paragraphs and (nested) bullet lists, preserving the PDF bullet
    /// characters. Ported from the SIRE Knowledge Bank's FlowDocument renderer.</summary>
    private static IEnumerable<Block> ParseBlocks(string text)
    {
        var blocks = new List<Block>();
        if (string.IsNullOrWhiteSpace(text)) return blocks;

        var lines = text.Replace("\r\n", "\n").Replace('\r', '\n').Split('\n');
        Paragraph? currentPara = null;
        bool inList = false;
        List list = new() { MarkerStyle = TextMarkerStyle.Disc };

        void FlushPara() { if (currentPara != null) { blocks.Add(currentPara); currentPara = null; } }
        void FlushList() { if (inList) { blocks.Add(list); inList = false; } }

        foreach (var rawLine in lines)
        {
            var line = rawLine.TrimEnd();
            var trimmed = line.TrimStart();

            bool isBullet = false, isSub = false;
            if (trimmed.Length > 1)
            {
                char c0 = trimmed[0];
                if (c0 is '•' or '·' or '–' or '—') isBullet = true;
                else if (trimmed.StartsWith("- ")) isBullet = true;
            }
            if (!isBullet && (line.StartsWith("    o ") || line.StartsWith("\to ") || trimmed.StartsWith("○ ")))
            { isBullet = true; isSub = true; }
            if (isBullet && (line.StartsWith("    ") || line.StartsWith("\t"))) isSub = true;

            if (isBullet)
            {
                FlushPara();
                if (!inList) { list = new List { MarkerStyle = TextMarkerStyle.Disc }; inList = true; }
                var bulletText = trimmed;
                foreach (var prefix in new[] { "• ", "•", "· ", "– ", "— ", "- ", "o ", "○ " })
                    if (bulletText.StartsWith(prefix)) { bulletText = bulletText[prefix.Length..].TrimStart(); break; }

                var itemPara = new Paragraph(new Run(bulletText)) { Margin = new Thickness(0, 1, 0, 1) };
                if (isSub && list.ListItems.Count > 0 && list.ListItems.LastListItem is ListItem last)
                {
                    var sub = last.Blocks.OfType<List>().LastOrDefault();
                    if (sub == null) { sub = new List { MarkerStyle = TextMarkerStyle.Circle }; last.Blocks.Add(sub); }
                    sub.ListItems.Add(new ListItem(itemPara));
                }
                else list.ListItems.Add(new ListItem(itemPara));
            }
            else
            {
                FlushList();
                if (string.IsNullOrWhiteSpace(line)) FlushPara();
                else
                {
                    if (currentPara == null) currentPara = new Paragraph { Margin = new Thickness(0, 0, 0, 6) };
                    else currentPara.Inlines.Add(new Run(" "));
                    currentPara.Inlines.Add(new Run(trimmed));
                }
            }
        }
        FlushList();
        FlushPara();
        if (blocks.Count == 0) blocks.Add(new Paragraph(new Run(text)));
        return blocks;
    }
}
