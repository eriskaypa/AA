using System;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;
using System.Xml;
using HtmlAgilityPack;

namespace AA.Services;

/// <summary>
/// Converts an HTML fragment from the clipboard into a WPF FlowDocument XAML string
/// that can be loaded into a RichTextBox via <c>TextRange.Load(stream, DataFormats.Xaml)</c>.
/// Produces only tags WPF's TextRange.Load accepts (Section / Paragraph / Run / Span /
/// Hyperlink / List / ListItem / LineBreak). CSS is parsed for the handful of properties
/// that map cleanly to WPF (color, background, font-weight, font-style, text-decoration,
/// font-family, font-size, text-align). Everything else is dropped so no raw CSS leaks.
/// </summary>
public static class HtmlToXamlConverter
{
    public static string Convert(string html)
    {
        if (string.IsNullOrWhiteSpace(html)) return string.Empty;
        var fragment = ExtractCfHtmlFragment(html);

        var doc = new HtmlDocument
        {
            OptionAutoCloseOnEnd = true,
            OptionFixNestedTags = true,
            OptionWriteEmptyNodes = true
        };
        doc.LoadHtml(fragment);

        // Strip non-content nodes before walking.
        foreach (var bad in doc.DocumentNode.Descendants()
                     .Where(n => n.Name is "script" or "style" or "meta" or "link" or "head" or "title")
                     .ToList())
            bad.Remove();

        var sb = new StringBuilder();
        using (var xw = XmlWriter.Create(sb, new XmlWriterSettings { OmitXmlDeclaration = true }))
        {
            xw.WriteStartElement("Section", "http://schemas.microsoft.com/winfx/2006/xaml/presentation");
            xw.WriteAttributeString("xml", "space", null, "preserve");

            var ctx = new Style();
            var paragraphOpen = false;
            EmitChildren(xw, doc.DocumentNode, ctx, ref paragraphOpen);
            if (paragraphOpen) xw.WriteEndElement();

            xw.WriteEndElement();
        }
        return sb.ToString();
    }

    /// <summary>WPF's clipboard HTML format prefixes the HTML with a header containing
    /// "StartHTML:" / "EndHTML:" / "StartFragment:" / "EndFragment:" offsets. Use the
    /// fragment range if present.</summary>
    private static string ExtractCfHtmlFragment(string html)
    {
        var sf = Regex.Match(html, @"StartFragment:(\d+)", RegexOptions.IgnoreCase);
        var ef = Regex.Match(html, @"EndFragment:(\d+)", RegexOptions.IgnoreCase);
        if (sf.Success && ef.Success
            && int.TryParse(sf.Groups[1].Value, out var s)
            && int.TryParse(ef.Groups[1].Value, out var e)
            && s >= 0 && e > s && e <= html.Length)
        {
            try { return html.Substring(s, e - s); } catch { /* fall through */ }
        }
        // Otherwise strip any "Version:" / "StartHTML:" / "EndHTML:" header lines.
        var headerEnd = Regex.Match(html, @"<\s*html", RegexOptions.IgnoreCase);
        if (headerEnd.Success) return html.Substring(headerEnd.Index);
        return html;
    }

    // ---- walker ----

    private class Style
    {
        public bool Bold;
        public bool Italic;
        public bool Underline;
        public bool Strike;
        public string? Foreground;
        public string? Background;
        public string? FontFamily;
        public double? FontSize;
        public string? Align; // Left/Center/Right/Justify
        public Style Clone() => (Style)MemberwiseClone();
    }

    private static readonly System.Collections.Generic.HashSet<string> InlineTags = new(StringComparer.OrdinalIgnoreCase)
    { "a","b","strong","i","em","u","s","strike","del","span","font","mark","sub","sup","code","tt","cite","abbr","big","small" };

    private static readonly System.Collections.Generic.HashSet<string> BlockTags = new(StringComparer.OrdinalIgnoreCase)
    { "p","div","section","article","header","footer","main","nav","aside","blockquote","pre","figure","figcaption",
      "h1","h2","h3","h4","h5","h6" };

    private static void EmitChildren(XmlWriter xw, HtmlNode parent, Style style, ref bool paragraphOpen)
    {
        foreach (var node in parent.ChildNodes)
        {
            switch (node.NodeType)
            {
                case HtmlNodeType.Text:
                    {
                        var text = HtmlEntity.DeEntitize(node.InnerText);
                        if (parent.Name is not ("pre" or "code"))
                            text = Regex.Replace(text, @"\s+", " ");
                        if (string.IsNullOrEmpty(text)) continue;
                        if (!paragraphOpen) { OpenParagraph(xw, style); paragraphOpen = true; }
                        WriteRun(xw, text, style);
                        break;
                    }
                case HtmlNodeType.Element:
                    HandleElement(xw, node, style, ref paragraphOpen);
                    break;
            }
        }
    }

    private static void HandleElement(XmlWriter xw, HtmlNode node, Style style, ref bool paragraphOpen)
    {
        var name = node.Name.ToLowerInvariant();
        switch (name)
        {
            case "br":
                if (!paragraphOpen) { OpenParagraph(xw, style); paragraphOpen = true; }
                xw.WriteStartElement("LineBreak");
                xw.WriteEndElement();
                return;

            case "hr":
                if (paragraphOpen) { xw.WriteEndElement(); paragraphOpen = false; }
                xw.WriteStartElement("Paragraph");
                xw.WriteAttributeString("BorderThickness", "0,0,0,1");
                xw.WriteAttributeString("BorderBrush", "#888");
                xw.WriteAttributeString("Padding", "0");
                xw.WriteEndElement();
                return;

            case "ul":
            case "ol":
                if (paragraphOpen) { xw.WriteEndElement(); paragraphOpen = false; }
                xw.WriteStartElement("List");
                xw.WriteAttributeString("MarkerStyle", name == "ol" ? "Decimal" : "Disc");
                foreach (var li in node.ChildNodes.Where(c => c.Name.Equals("li", StringComparison.OrdinalIgnoreCase)))
                {
                    xw.WriteStartElement("ListItem");
                    var liParaOpen = false;
                    var liStyle = MergeStyle(style, li);
                    EmitChildren(xw, li, liStyle, ref liParaOpen);
                    if (liParaOpen) xw.WriteEndElement();
                    xw.WriteEndElement();
                }
                xw.WriteEndElement();
                return;

            case "li":
                // handled by parent ul/ol; if encountered raw, treat as paragraph
                if (paragraphOpen) { xw.WriteEndElement(); paragraphOpen = false; }
                {
                    var s = MergeStyle(style, node);
                    var open = false;
                    OpenParagraph(xw, s); open = true;
                    EmitChildren(xw, node, s, ref open);
                    if (open) xw.WriteEndElement();
                }
                return;

            case "table":
                // Convert to a real WPF FlowDocument Table so pasted tables (from Excel / Word / the
                // web) keep their grid structure and can be copied back out intact.
                if (paragraphOpen) { xw.WriteEndElement(); paragraphOpen = false; }
                EmitTable(xw, node, MergeStyle(style, node));
                return;
        }

        var merged = MergeStyle(style, node);

        if (BlockTags.Contains(name))
        {
            if (paragraphOpen) { xw.WriteEndElement(); paragraphOpen = false; }

            if (name is "h1" or "h2" or "h3" or "h4" or "h5" or "h6")
            {
                merged.Bold = true;
                merged.FontSize ??= name switch
                {
                    "h1" => 22, "h2" => 18, "h3" => 16, "h4" => 14, "h5" => 13, _ => 12
                };
            }
            if (name == "blockquote")
            {
                OpenParagraph(xw, merged, indent: "20,0,0,0");
            }
            else
            {
                OpenParagraph(xw, merged);
            }
            paragraphOpen = true;
            EmitChildren(xw, node, merged, ref paragraphOpen);
            if (paragraphOpen) { xw.WriteEndElement(); paragraphOpen = false; }
            return;
        }

        if (InlineTags.Contains(name))
        {
            switch (name)
            {
                case "b": case "strong": merged.Bold = true; break;
                case "i": case "em": case "cite": merged.Italic = true; break;
                case "u": merged.Underline = true; break;
                case "s": case "strike": case "del": merged.Strike = true; break;
            }

            if (!paragraphOpen) { OpenParagraph(xw, style); paragraphOpen = true; }

            if (name == "a")
            {
                var href = node.GetAttributeValue("href", "");
                xw.WriteStartElement("Hyperlink");
                if (!string.IsNullOrWhiteSpace(href))
                {
                    xw.WriteAttributeString("NavigateUri", href);
                }
                WriteStyleAttrs(xw, merged, isHyperlink: true);
                EmitInlineChildren(xw, node, merged);
                xw.WriteEndElement();
            }
            else
            {
                xw.WriteStartElement("Span");
                WriteStyleAttrs(xw, merged);
                EmitInlineChildren(xw, node, merged);
                xw.WriteEndElement();
            }
            return;
        }

        // Unknown element: emit children inline with merged style.
        EmitChildren(xw, node, merged, ref paragraphOpen);
    }

    /// <summary>Emit an HTML &lt;table&gt; as a WPF FlowDocument Table (Table.Columns / TableRowGroup /
    /// TableRow / TableCell), with visible cell borders and header cells bolded.</summary>
    private static void EmitTable(XmlWriter xw, HtmlNode table, Style style)
    {
        // Only THIS table's own rows — a <tr> whose nearest ancestor <table> is this one. Without
        // this filter, Descendants("tr") also collects the rows of any nested table and appends them
        // as spurious extra rows (and the nested content, being flattened into its cell too, would
        // otherwise appear twice).
        bool OwnedByThisTable(HtmlNode tr)
        {
            for (var a = tr.ParentNode; a != null; a = a.ParentNode)
            {
                if (a == table) return true;
                if (a.Name.Equals("table", StringComparison.OrdinalIgnoreCase)) return false;
            }
            return false;
        }
        var rows = table.Descendants("tr").Where(OwnedByThisTable).ToList();
        if (rows.Count == 0) return;
        int Cells(HtmlNode r) => r.ChildNodes.Where(c => c.Name is "td" or "th")
            .Sum(c => Math.Max(1, c.GetAttributeValue("colspan", 1)));
        int cols = rows.Max(Cells);
        if (cols == 0) return;

        xw.WriteStartElement("Table");
        xw.WriteAttributeString("CellSpacing", "0");
        xw.WriteAttributeString("Margin", "0,4,0,4");

        xw.WriteStartElement("Table.Columns");
        for (int i = 0; i < cols; i++) { xw.WriteStartElement("TableColumn"); xw.WriteEndElement(); }
        xw.WriteEndElement();

        xw.WriteStartElement("TableRowGroup");
        foreach (var row in rows)
        {
            var rowStyle = MergeStyle(style, row);
            xw.WriteStartElement("TableRow");
            foreach (var cell in row.ChildNodes.Where(c => c.Name is "td" or "th"))
            {
                var cellStyle = MergeStyle(rowStyle, cell);
                if (cell.Name.Equals("th", StringComparison.OrdinalIgnoreCase)) cellStyle.Bold = true;

                xw.WriteStartElement("TableCell");
                xw.WriteAttributeString("BorderBrush", "#FF9AA0A6");
                xw.WriteAttributeString("BorderThickness", "0.6");
                xw.WriteAttributeString("Padding", "3,1,3,1");
                var colspan = Math.Max(1, cell.GetAttributeValue("colspan", 1));
                var rowspan = Math.Max(1, cell.GetAttributeValue("rowspan", 1));
                if (colspan > 1) xw.WriteAttributeString("ColumnSpan", colspan.ToString(CultureInfo.InvariantCulture));
                if (rowspan > 1) xw.WriteAttributeString("RowSpan", rowspan.ToString(CultureInfo.InvariantCulture));

                xw.WriteStartElement("Paragraph");
                if (!string.IsNullOrEmpty(cellStyle.Align)) xw.WriteAttributeString("TextAlignment", cellStyle.Align);
                EmitInlineChildren(xw, cell, cellStyle);
                xw.WriteEndElement(); // Paragraph
                xw.WriteEndElement(); // TableCell
            }
            xw.WriteEndElement(); // TableRow
        }
        xw.WriteEndElement(); // TableRowGroup
        xw.WriteEndElement(); // Table
    }

    private static void EmitInlineChildren(XmlWriter xw, HtmlNode parent, Style style)
    {
        foreach (var node in parent.ChildNodes)
        {
            switch (node.NodeType)
            {
                case HtmlNodeType.Text:
                    {
                        var text = HtmlEntity.DeEntitize(node.InnerText);
                        if (parent.Name is not ("pre" or "code"))
                            text = Regex.Replace(text, @"\s+", " ");
                        if (string.IsNullOrEmpty(text)) continue;
                        WriteRun(xw, text, style);
                        break;
                    }
                case HtmlNodeType.Element:
                    var name = node.Name.ToLowerInvariant();
                    if (name == "br") { xw.WriteStartElement("LineBreak"); xw.WriteEndElement(); break; }
                    var s = MergeStyle(style, node);
                    switch (name)
                    {
                        case "b": case "strong": s.Bold = true; break;
                        case "i": case "em": case "cite": s.Italic = true; break;
                        case "u": s.Underline = true; break;
                        case "s": case "strike": case "del": s.Strike = true; break;
                    }
                    if (name == "a")
                    {
                        var href = node.GetAttributeValue("href", "");
                        xw.WriteStartElement("Hyperlink");
                        if (!string.IsNullOrWhiteSpace(href)) xw.WriteAttributeString("NavigateUri", href);
                        WriteStyleAttrs(xw, s, isHyperlink: true);
                        EmitInlineChildren(xw, node, s);
                        xw.WriteEndElement();
                    }
                    else
                    {
                        xw.WriteStartElement("Span");
                        WriteStyleAttrs(xw, s);
                        EmitInlineChildren(xw, node, s);
                        xw.WriteEndElement();
                    }
                    break;
            }
        }
    }

    private static void OpenParagraph(XmlWriter xw, Style s, string? indent = null)
    {
        xw.WriteStartElement("Paragraph");
        if (!string.IsNullOrEmpty(s.Align))
            xw.WriteAttributeString("TextAlignment", s.Align);
        if (indent != null) xw.WriteAttributeString("Margin", indent);
    }

    private static void WriteRun(XmlWriter xw, string text, Style s)
    {
        xw.WriteStartElement("Run");
        WriteStyleAttrs(xw, s);
        xw.WriteString(text);
        xw.WriteEndElement();
    }

    private static void WriteStyleAttrs(XmlWriter xw, Style s, bool isHyperlink = false)
    {
        if (s.Bold) xw.WriteAttributeString("FontWeight", "Bold");
        if (s.Italic) xw.WriteAttributeString("FontStyle", "Italic");
        var deco = (s.Underline, s.Strike) switch
        {
            (true, true) => "Underline,Strikethrough",
            (true, false) => "Underline",
            (false, true) => "Strikethrough",
            _ => null
        };
        if (deco != null) xw.WriteAttributeString("TextDecorations", deco);
        if (!isHyperlink && !string.IsNullOrEmpty(s.Foreground))
            xw.WriteAttributeString("Foreground", s.Foreground);
        if (!string.IsNullOrEmpty(s.Background))
            xw.WriteAttributeString("Background", s.Background);
        if (!string.IsNullOrEmpty(s.FontFamily))
            xw.WriteAttributeString("FontFamily", s.FontFamily);
        if (s.FontSize.HasValue)
            xw.WriteAttributeString("FontSize", s.FontSize.Value.ToString("0.##", CultureInfo.InvariantCulture));
    }

    // ---- inline style merging ----

    private static Style MergeStyle(Style parent, HtmlNode node)
    {
        var s = parent.Clone();
        var name = node.Name.ToLowerInvariant();
        // Legacy attributes
        var color = node.GetAttributeValue("color", null);
        if (!string.IsNullOrEmpty(color)) s.Foreground = NormaliseColor(color);
        var face = node.GetAttributeValue("face", null);
        if (!string.IsNullOrEmpty(face)) s.FontFamily = face;
        var size = node.GetAttributeValue("size", null);
        if (!string.IsNullOrEmpty(size) && double.TryParse(size, NumberStyles.Any, CultureInfo.InvariantCulture, out var sz)) s.FontSize = 8 + sz * 2;
        var align = node.GetAttributeValue("align", null);
        if (!string.IsNullOrEmpty(align)) s.Align = MapAlign(align);

        var styleAttr = node.GetAttributeValue("style", null);
        if (!string.IsNullOrEmpty(styleAttr)) ApplyCss(s, styleAttr);

        return s;
    }

    private static void ApplyCss(Style s, string css)
    {
        foreach (var raw in css.Split(';'))
        {
            var part = raw.Trim();
            if (part.Length == 0) continue;
            var i = part.IndexOf(':');
            if (i <= 0) continue;
            var key = part.Substring(0, i).Trim().ToLowerInvariant();
            var val = part.Substring(i + 1).Trim();
            switch (key)
            {
                case "font-weight":
                    if (val == "bold" || val == "bolder" || (int.TryParse(val, out var w) && w >= 600))
                        s.Bold = true;
                    else if (val == "normal" || val == "lighter") s.Bold = false;
                    break;
                case "font-style":
                    if (val == "italic" || val == "oblique") s.Italic = true;
                    else if (val == "normal") s.Italic = false;
                    break;
                case "text-decoration":
                case "text-decoration-line":
                    if (val.Contains("underline")) s.Underline = true;
                    if (val.Contains("line-through")) s.Strike = true;
                    if (val == "none") { s.Underline = false; s.Strike = false; }
                    break;
                case "color":
                    {
                        var c = NormaliseColor(val);
                        if (c != null) s.Foreground = c;
                        break;
                    }
                case "background-color":
                case "background":
                    {
                        var c = NormaliseColor(val);
                        if (c != null) s.Background = c;
                        break;
                    }
                case "font-family":
                    s.FontFamily = val.Trim('"', '\'');
                    break;
                case "font-size":
                    {
                        var px = ParseLengthPx(val);
                        if (px.HasValue) s.FontSize = px.Value;
                        break;
                    }
                case "text-align":
                    s.Align = MapAlign(val);
                    break;
            }
        }
    }

    private static string MapAlign(string val) => val.Trim().ToLowerInvariant() switch
    {
        "center" => "Center",
        "right" => "Right",
        "justify" => "Justify",
        _ => "Left"
    };

    private static double? ParseLengthPx(string val)
    {
        val = val.Trim();
        var m = Regex.Match(val, @"^([\d.]+)\s*(px|pt|em|rem|%)?$", RegexOptions.IgnoreCase);
        if (!m.Success) return null;
        if (!double.TryParse(m.Groups[1].Value, NumberStyles.Any, CultureInfo.InvariantCulture, out var n)) return null;
        return m.Groups[2].Value.ToLowerInvariant() switch
        {
            "pt" => n * 1.333,
            "em" or "rem" => n * 14,
            "%" => 14 * n / 100,
            _ => n
        };
    }

    /// <summary>Known WPF colour names (the exact set its XAML parser accepts), built once from
    /// <see cref="System.Windows.Media.Colors"/>. Used to reject CSS colours WPF doesn't understand
    /// (e.g. rebeccapurple, lightgrey, currentColor, inherit) rather than emitting them and having
    /// TextRange.Load reject the whole styled paste.</summary>
    private static readonly System.Collections.Generic.HashSet<string> KnownColorNames = BuildKnownColorNames();

    private static System.Collections.Generic.HashSet<string> BuildKnownColorNames()
    {
        var set = new System.Collections.Generic.HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var p in typeof(System.Windows.Media.Colors)
                     .GetProperties(System.Reflection.BindingFlags.Public | System.Reflection.BindingFlags.Static))
            set.Add(p.Name);
        return set;
    }

    private static string? NormaliseColor(string c)
    {
        c = c.Trim();
        if (c.Length == 0) return null;
        if (c.StartsWith("#"))
        {
            // WPF's parser accepts only #RGB, #ARGB, #RRGGBB, #AARRGGBB. Anything else (e.g. #xyz,
            // #12) would make the whole styled paste fail to load, so drop it.
            var hex = c.Substring(1);
            return (hex.Length is 3 or 4 or 6 or 8) && hex.All(Uri.IsHexDigit) ? c : null;
        }
        var rgb = Regex.Match(c, @"^rgba?\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*(?:,\s*([\d.]+)\s*)?\)$", RegexOptions.IgnoreCase);
        if (rgb.Success)
        {
            // Clamp channels to 0-255 so out-of-range CSS (rgb(999,...)) can't produce malformed hex.
            static int Clamp(string s) => (int)Math.Clamp(
                long.TryParse(s, NumberStyles.Integer, CultureInfo.InvariantCulture, out var v) ? v : 255L, 0, 255);
            return $"#{Clamp(rgb.Groups[1].Value):X2}{Clamp(rgb.Groups[2].Value):X2}{Clamp(rgb.Groups[3].Value):X2}";
        }
        // Named colours: only pass through ones WPF actually knows.
        if (Regex.IsMatch(c, @"^[A-Za-z]+$") && KnownColorNames.Contains(c)) return c;
        return null;
    }
}
