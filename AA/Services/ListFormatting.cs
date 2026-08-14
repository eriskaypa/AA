using System;
using System.Collections.Generic;
using System.Linq;
using System.Windows;
using System.Windows.Documents;

namespace AA.Services;

/// <summary>List building and tidying for the rich-text container body.
///
/// WPF's own list commands are kept and used — they already get Enter, Tab and Shift+Tab right. What they
/// do not do is make the result *look* right: every nested list carries an automatic margin that shows up
/// as a full blank line, the indent step is roughly double LibreOffice's, and every level draws the same
/// marker. Everything here is a post-pass over what WPF produced, which is why it must run AFTER a list
/// command rather than before — those commands rebuild paragraphs and discard explicit margins.</summary>
public static class ListFormatting
{
    /// <summary>Indent per level. WPF defaults to ~49px, about twice LibreOffice's step, which makes a
    /// three-deep list run off the side of a narrow container.</summary>
    public const double IndentStep = 24;

    /// <summary>Bullet markers by depth, matching LibreOffice Writer: filled, hollow, square, then repeat.</summary>
    private static readonly TextMarkerStyle[] BulletCycle =
        { TextMarkerStyle.Disc, TextMarkerStyle.Circle, TextMarkerStyle.Square };

    /// <summary>Number markers by depth, matching Writer: 1. then a. then i., then repeat.</summary>
    private static readonly TextMarkerStyle[] NumberCycle =
        { TextMarkerStyle.Decimal, TextMarkerStyle.LowerLatin, TextMarkerStyle.LowerRoman };

    /// <summary>Build a list from plain text lines. Blank lines are dropped rather than becoming empty
    /// bullets — importing a saved list should not import its gaps.</summary>
    public static List Build(IEnumerable<string> lines, bool numbered)
    {
        var list = new List { MarkerStyle = numbered ? TextMarkerStyle.Decimal : TextMarkerStyle.Disc };
        foreach (var line in lines)
        {
            if (string.IsNullOrWhiteSpace(line)) continue;
            list.ListItems.Add(new ListItem(Item(line.Trim())));
        }
        ApplySpacing(list, 0, numbered);
        return list;
    }

    /// <summary>Build a list whose entries may carry sub-lines, which become one nested level.</summary>
    public static List Build(IEnumerable<(string Text, IReadOnlyList<string> Children)> entries, bool numbered)
    {
        var list = new List { MarkerStyle = numbered ? TextMarkerStyle.Decimal : TextMarkerStyle.Disc };
        foreach (var (text, children) in entries)
        {
            if (string.IsNullOrWhiteSpace(text)) continue;
            var li = new ListItem(Item(text.Trim()));
            var kids = (children ?? Array.Empty<string>()).Where(c => !string.IsNullOrWhiteSpace(c)).ToList();
            if (kids.Count > 0)
            {
                var sub = new List();
                foreach (var k in kids) sub.ListItems.Add(new ListItem(Item(k.Trim())));
                li.Blocks.Add(sub);
            }
            list.ListItems.Add(li);
        }
        ApplySpacing(list, 0, numbered);
        return list;
    }

    private static Paragraph Item(string text) => new(new Run(text)) { Margin = new Thickness(0, 1, 0, 1) };

    /// <summary>Re-apply per-depth markers, indent and spacing to every list in a document. Safe to run
    /// repeatedly; call it after any list command so WPF's defaults never survive to the screen.</summary>
    public static void Normalise(FlowDocument? doc)
    {
        if (doc == null) return;
        foreach (var list in doc.Blocks.OfType<List>()) ApplySpacing(list, 0, IsNumbered(list.MarkerStyle));
        foreach (var block in doc.Blocks) NormaliseWithin(block);
    }

    private static void NormaliseWithin(Block block)
    {
        switch (block)
        {
            case List list:
                foreach (var li in list.ListItems)
                    foreach (var b in li.Blocks) NormaliseWithin(b);
                break;
            case Table table:
                foreach (var g in table.RowGroups)
                    foreach (var r in g.Rows)
                        foreach (var c in r.Cells)
                        {
                            foreach (var l in c.Blocks.OfType<List>()) ApplySpacing(l, 0, IsNumbered(l.MarkerStyle));
                            foreach (var b in c.Blocks) NormaliseWithin(b);
                        }
                break;
            case Section section:
                foreach (var l in section.Blocks.OfType<List>()) ApplySpacing(l, 0, IsNumbered(l.MarkerStyle));
                foreach (var b in section.Blocks) NormaliseWithin(b);
                break;
        }
    }

    /// <summary>Set marker, indent and margins for a list and everything nested inside it.</summary>
    private static void ApplySpacing(List list, int depth, bool numbered)
    {
        var cycle = numbered ? NumberCycle : BulletCycle;
        list.MarkerStyle = cycle[depth % cycle.Length];
        list.Padding = new Thickness(IndentStep, 0, 0, 0);
        // Only the outermost list gets breathing room. A nested list's default margin renders as a whole
        // blank line above and below it, which is what makes an imported checklist look padded out.
        list.Margin = depth == 0 ? new Thickness(0, 6, 0, 6) : new Thickness(0);

        foreach (var li in list.ListItems)
        {
            foreach (var p in li.Blocks.OfType<Paragraph>())
                p.Margin = new Thickness(0, 1, 0, 1);
            foreach (var sub in li.Blocks.OfType<List>())
                ApplySpacing(sub, depth + 1, numbered || IsNumbered(sub.MarkerStyle));
        }
    }

    private static bool IsNumbered(TextMarkerStyle s) =>
        s is TextMarkerStyle.Decimal or TextMarkerStyle.LowerLatin or TextMarkerStyle.UpperLatin
          or TextMarkerStyle.LowerRoman or TextMarkerStyle.UpperRoman;

    /// <summary>How deep a list is nested inside the document (1 = top level).</summary>
    public static int DepthOf(List? list)
    {
        int d = 0;
        DependencyObject? node = list;
        while (node != null)
        {
            if (node is List) d++;
            node = node switch
            {
                FrameworkContentElement fce => fce.Parent,
                _ => null
            };
        }
        return d;
    }
}
