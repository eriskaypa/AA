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

    // ---------- Reordering (LibreOffice's Move Up / Move Down) ----------

    /// <summary>Move a list item among its siblings. Anything nested inside it travels with it, because
    /// a sub-list lives in the item's own Blocks — moving the item moves its children by construction,
    /// which is what makes reordering a checklist safe rather than a way to orphan sub-steps.
    /// Returns false at the ends of a list, where there is nowhere to go.</summary>
    public static bool MoveItem(ListItem? item, bool up)
    {
        // Take the collection from the owning List, NOT from item.SiblingListItems: that property is the
        // collection the item belongs to, and removing the item detaches the reference, after which
        // InsertBefore/After throws "PreviousSibling does not belong to this TextElementCollection".
        if (item?.Parent is not List owner) return false;
        var neighbour = up ? item.PreviousListItem : item.NextListItem;
        if (neighbour == null) return false;

        var items = owner.ListItems;
        items.Remove(item);
        if (up) items.InsertBefore(neighbour, item);
        else items.InsertAfter(neighbour, item);
        return true;
    }

    /// <summary>Move a contiguous run of sibling list items as one group, keeping their relative order.</summary>
    public static bool MoveItems(IReadOnlyList<ListItem> items, bool up)
    {
        if (items == null || items.Count == 0) return false;
        if (items.Count == 1) return MoveItem(items[0], up);

        // Every item must share one owning list, or "move together" has no meaning.
        if (items[0].Parent is not List owner) return false;
        if (items.Any(i => !ReferenceEquals(i.Parent, owner))) return false;

        var siblings = owner.ListItems;
        var ordered = OrderBySiblingPosition(items, siblings);
        var neighbour = up ? ordered[0].PreviousListItem : ordered[^1].NextListItem;
        if (neighbour == null) return false;

        foreach (var i in ordered) siblings.Remove(i);
        // Re-insert in order, anchoring off the neighbour we hopped over.
        ListItem anchor = neighbour;
        if (up)
        {
            foreach (var i in ordered) siblings.InsertBefore(anchor, i);
        }
        else
        {
            foreach (var i in ordered) { siblings.InsertAfter(anchor, i); anchor = i; }
        }
        return true;
    }

    private static List<ListItem> OrderBySiblingPosition(IReadOnlyList<ListItem> items, ListItemCollection siblings)
    {
        var order = new List<ListItem>();
        for (var it = siblings.FirstListItem; it != null; it = it.NextListItem)
            if (items.Contains(it)) order.Add(it);
        return order;
    }

    /// <summary>Move a whole block (a paragraph, an entire list, a table) among its siblings — how a
    /// user reorders one inserted list relative to the rest of the note.</summary>
    public static bool MoveBlock(Block? block, bool up)
    {
        // Same trap as MoveItem: take the collection from the PARENT, not from block.SiblingBlocks.
        var blocks = BlocksOf(block?.Parent);
        if (block == null || blocks == null) return false;
        var neighbour = up ? block.PreviousBlock : block.NextBlock;
        if (neighbour == null) return false;

        blocks.Remove(block);
        if (up) blocks.InsertBefore(neighbour, block);
        else blocks.InsertAfter(neighbour, block);
        return true;
    }

    /// <summary>The Blocks collection of whatever can hold blocks, or null if this parent cannot.</summary>
    private static BlockCollection? BlocksOf(DependencyObject? parent) => parent switch
    {
        FlowDocument fd => fd.Blocks,
        ListItem li => li.Blocks,
        TableCell tc => tc.Blocks,
        Section s => s.Blocks,
        Floater f => f.Blocks,
        Figure fig => fig.Blocks,
        _ => null
    };

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
