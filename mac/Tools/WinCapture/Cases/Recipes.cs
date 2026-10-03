// Remaining automated recipes W07–W18 (spec 01 GF.6.5): one static method each, same helpers as Program.cs.
// Handlers of ContainerEditor.xaml.cs / SirePage.xaml.cs that are not linkable (they live in WPF code-behind) are
// replicated VERBATIM below and marked with their source lines.
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Documents;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using AA.Services;
using AA.Sire;
using static WinCapture.Program;

namespace WinCapture;

internal static class Recipes
{
    private const string NS = "xmlns=\"http://schemas.microsoft.com/winfx/2006/xaml/presentation\"";

    // ---- verbatim replicas ------------------------------------------------------------------------------------

    /// <summary>ContainerEditor.Strike_Click (ContainerEditor.xaml.cs:591-596), verbatim.</summary>
    internal static void StrikeClick(RichTextBox Rtb)
    {
        var cur = Rtb.Selection.GetPropertyValue(Inline.TextDecorationsProperty) as TextDecorationCollection;
        Rtb.Selection.ApplyPropertyValue(Inline.TextDecorationsProperty,
            cur != null && cur.Count > 0 && cur[0] == TextDecorations.Strikethrough[0] ? null : TextDecorations.Strikethrough);
    }

    /// <summary>ContainerEditor.ClearFormat_Click (ContainerEditor.xaml.cs:693-703), verbatim except that the
    /// EditorFg resource is the App.xaml value #FF1A1A1A (there is no App resource dictionary here).</summary>
    internal static void ClearFormatting(RichTextBox Rtb)
    {
        var sel = Rtb.Selection;
        sel.ApplyPropertyValue(TextElement.FontWeightProperty, FontWeights.Normal);
        sel.ApplyPropertyValue(TextElement.FontStyleProperty, FontStyles.Normal);
        sel.ApplyPropertyValue(Inline.TextDecorationsProperty, null);
        sel.ApplyPropertyValue(TextElement.ForegroundProperty, new SolidColorBrush(Color.FromArgb(0xFF, 0x1A, 0x1A, 0x1A)));
        sel.ApplyPropertyValue(TextElement.BackgroundProperty, null);
    }

    /// <summary>ContainerEditor.OnRtbPasting (ContainerEditor.xaml.cs:354-383), verbatim.</summary>
    internal static void OnRtbPastingReplica(object sender, DataObjectPastingEventArgs e)
    {
        try
        {
            var d = e.SourceDataObject;
            // Already a high-fidelity rich format — let WPF handle it natively.
            if (d.GetDataPresent(DataFormats.Xaml) || d.GetDataPresent(DataFormats.XamlPackage)
                || d.GetDataPresent(DataFormats.Rtf))
                return;

            if (!d.GetDataPresent(DataFormats.Html)) return;
            var html = d.GetData(DataFormats.Html) as string;
            if (string.IsNullOrWhiteSpace(html)) return;

            var xaml = AA.Services.HtmlToXamlConverter.Convert(html);
            if (string.IsNullOrWhiteSpace(xaml)) return;

            var newData = new DataObject();
            newData.SetData(DataFormats.Xaml, xaml);
            // Provide a plain-text fallback so Word/other targets still get something useful.
            var plain = d.GetData(DataFormats.UnicodeText) as string ?? d.GetData(DataFormats.Text) as string;
            if (!string.IsNullOrEmpty(plain)) newData.SetData(DataFormats.UnicodeText, plain);
            e.DataObject = newData;
            e.FormatToApply = DataFormats.Xaml;
        }
        catch
        {
            // On any failure, fall back to default paste behavior.
        }
    }

    private static void SelectAll(RichTextBox r) => r.Selection.Select(r.Document.ContentStart, r.Document.ContentEnd);

    // ---- W07: toggle semantics; strike reference comparison ------------------------------------------------------
    public static void W07()
    {
        const string S = "05 CONT-023 (182); 05:566";
        var a = NewEditor(); TypeText(a, "normal"); SelectAll(a); EditingCommands.ToggleBold.Execute(null, a);
        Emit("W07a-bold", Save(a), "type, select all, ToggleBold", S);
        EditingCommands.ToggleBold.Execute(null, a); Emit("W07b-bold-again", Save(a), "ToggleBold again", S); Done(a);

        var c = NewEditor(); TypeText(c, "one two"); Select(c, "two"); EditingCommands.ToggleBold.Execute(null, c);
        SelectAll(c); EditingCommands.ToggleBold.Execute(null, c); Emit("W07c-mixed-bold", Save(c), "only 'two' bold, select all, ToggleBold", S); Done(c);

        var d = NewEditor(); TypeText(d, "semi"); SelectAll(d); d.Selection.ApplyPropertyValue(TextElement.FontWeightProperty, FontWeights.SemiBold);
        EditingCommands.ToggleBold.Execute(null, d); Emit("W07d-semibold", Save(d), "SemiBold then ToggleBold", S); Done(d);

        var e = NewEditor(); TypeText(e, "one two"); Select(e, "two"); EditingCommands.ToggleItalic.Execute(null, e);
        SelectAll(e); EditingCommands.ToggleItalic.Execute(null, e); Emit("W07e-mixed-italic", Save(e), "ToggleItalic on a mixed selection", S); Done(e);

        var f = NewEditor(); TypeText(f, "both"); SelectAll(f);
        f.Selection.ApplyPropertyValue(Inline.TextDecorationsProperty, new TextDecorationCollection { TextDecorations.Underline[0], TextDecorations.Strikethrough[0] });
        EditingCommands.ToggleUnderline.Execute(null, f); Emit("W07f-underline-strike", Save(f), "underline + strike, ToggleUnderline", S); Done(f);

        var g1 = NewEditor(); TypeText(g1, "typed"); SelectAll(g1); StrikeClick(g1); Emit("W07g1-strike-typed", Save(g1), "Strike_Click on typed text", S);
        StrikeClick(g1); Emit("W07g2-strike-typed-again", Save(g1), "Strike_Click again (reference comparison with Strikethrough[0])", S); Done(g1);
        var g3 = NewEditor(); Load(g3, $"<Section {NS}><Paragraph><Run TextDecorations=\"Strikethrough\">x</Run></Paragraph></Section>");
        SelectAll(g3); StrikeClick(g3); Emit("W07g3-strike-loaded", Save(g3), "Strike_Click on a strike loaded from XAML", S); Done(g3);
        var g4 = NewEditor(); TypeText(g4, "under"); SelectAll(g4); EditingCommands.ToggleUnderline.Execute(null, g4); StrikeClick(g4);
        Emit("W07g4-strike-on-underline", Save(g4), "Strike_Click on underline-only text", S); Done(g4);
    }

    // ---- W08: list commands, before and after ListFormatting.Normalise --------------------------------------------
    private static RichTextBox ThreeParagraphs()
    {
        var r = NewEditor();
        TypeText(r, "A"); EditingCommands.EnterParagraphBreak.Execute(null, r);
        TypeText(r, "B"); EditingCommands.EnterParagraphBreak.Execute(null, r);
        TypeText(r, "C");
        return r;
    }

    private static void Caret(RichTextBox r, string needle, bool end)
    {
        var range = Find(r.Document, needle);
        var p = end ? range.End : range.Start;
        r.Selection.Select(p, p);
    }

    private static void ListStep(string id, string what, RichTextBox r, Action<RichTextBox> act)
    {
        act(r);
        Emit(id + "-raw", Save(r), what + " (raw WPF)", "05 CONT-040/041/043 (290); CONT-044 (307)", mac: false);
        ListFormatting.Normalise(r.Document);
        Emit(id + "-normalised", Save(r), what + " then ListFormatting.Normalise", "05 CONT-040/041/043 (290); 05 S-2/S-3");
    }

    public static void W08()
    {
        var r = ThreeParagraphs();
        ListStep("W08a-bullets", "select all → ToggleBullets", r, x => { SelectAll(x); EditingCommands.ToggleBullets.Execute(null, x); });
        ListStep("W08b-bullets-off", "ToggleBullets again", r, x => { SelectAll(x); EditingCommands.ToggleBullets.Execute(null, x); });
        Done(r);
        var n = ThreeParagraphs();
        SelectAll(n); EditingCommands.ToggleBullets.Execute(null, n);
        ListStep("W08c-numbering-on-bullets", "ToggleNumbering on bullets", n, x => { SelectAll(x); EditingCommands.ToggleNumbering.Execute(null, x); });
        ListStep("W08d-indent", "caret in B → IncreaseIndentation", n, x => { Caret(x, "B", false); EditingCommands.IncreaseIndentation.Execute(null, x); });
        ListStep("W08e-outdent", "caret in B → DecreaseIndentation", n, x => { Caret(x, "B", false); EditingCommands.DecreaseIndentation.Execute(null, x); });
        ListStep("W08f-enter", "caret at end of C → EnterParagraphBreak", n, x => { Caret(x, "C", true); EditingCommands.EnterParagraphBreak.Execute(null, x); });
        ListStep("W08g-enter-empty", "EnterParagraphBreak again on the new empty item", n, x => EditingCommands.EnterParagraphBreak.Execute(null, x));
        ListStep("W08h-tab", "caret at start of B → TabForward", n, x => { Caret(x, "B", false); EditingCommands.TabForward.Execute(null, x); });
        ListStep("W08i-shift-tab", "caret at start of B → TabBackward", n, x => { Caret(x, "B", false); EditingCommands.TabBackward.Execute(null, x); });
        Done(n);
        var p = NewEditor(); TypeText(p, "plain paragraph");
        ListStep("W08j-plain-indent", "a plain paragraph → IncreaseIndentation (WPF TextIndent)", p, x => EditingCommands.IncreaseIndentation.Execute(null, x));
        Done(p);
    }

    // ---- W09: ListFormatting.Build / Normalise outputs ------------------------------------------------------------
    public static void W09()
    {
        foreach (var numbered in new[] { true, false })
        {
            var r = NewEditor(); r.Document.Blocks.Clear();
            r.Document.Blocks.Add(ListFormatting.Build(new[] { "Check oil  (60 min)", "Log" }, numbered));
            Emit(numbered ? "W09a-build-numbered" : "W09b-build-bullets", Save(r), $"ListFormatting.Build(…, numbered: {numbered})", "05 S-2; 05 S-3");
            Done(r);
        }
        var nested = ThreeParagraphs();
        SelectAll(nested); EditingCommands.ToggleBullets.Execute(null, nested);
        Caret(nested, "B", false); EditingCommands.IncreaseIndentation.Execute(null, nested);
        ListFormatting.Normalise(nested.Document);
        Emit("W09c-nested-normalised", Save(nested), "a nested list (B indented) normalised", "05 S-2; 05 S-3");
        Done(nested);
    }

    // ---- W10: undo after a programmatic load ------------------------------------------------------------------------
    public static void W10()
    {
        var r = NewEditor();
        var a = $"<Section {NS}><Paragraph><Run>first body</Run></Paragraph></Section>";
        var b = $"<Section {NS}><Paragraph><Run>second body</Run></Paragraph></Section>";
        Load(r, a);
        Load(r, b);                                      // as ContainerEditor.Load does: no clear of the undo stack
        var canUndo = r.CanUndo;
        r.Undo();
        var after = Save(r);
        Emit("W10-undo-after-load", after, "Load(A); Load(B); Undo() — what an undo after a programmatic load restores", "05 CONT-011 (157); 05 D-2", mac: false);
        EmitJson("W10-undo-state", new JsonObject { ["canUndoAfterTwoLoads"] = canUndo, ["canUndoAfterUndo"] = r.CanUndo }, "undo state after programmatic loads", "05 CONT-011 (157); 05 D-2");
        Done(r);
    }

    // ---- W11: RTF → XAML (TextRange.Load(Rtf) and the paste path) -----------------------------------------------
    public static void W11()
    {
        var inputs = Path.Combine(Out, "inputs");
        if (!Directory.Exists(inputs)) { Console.WriteLine("W11: no inputs/R-*.rtf captured yet (GF.6.6) — skipped"); return; }
        foreach (var file in Directory.GetFiles(inputs, "R-*.rtf").OrderBy(x => x, StringComparer.Ordinal))
        {
            var id = Path.GetFileNameWithoutExtension(file);
            var rtf = File.ReadAllText(file, Encoding.UTF8);
            var doc = new FlowDocument();
            using (var ms = new MemoryStream(Encoding.UTF8.GetBytes(rtf)))
                new TextRange(doc.ContentStart, doc.ContentEnd).Load(ms, DataFormats.Rtf);
            Emit($"W11-{id}.load", Save(doc), $"TextRange.Load({id}.rtf, Rtf)", "05 §9 Q1", inputs: new JsonObject { ["rtf"] = "inputs/" + Path.GetFileName(file) });

            var r = NewEditor();
            TypeText(r, "Before ");
            DataObject.AddPastingHandler(r, OnRtbPastingReplica);
            Clipboard.SetDataObject(new DataObject(DataFormats.Rtf, rtf));
            r.Paste();
            TypeText(r, " After");
            Emit($"W11-{id}.pasted", Save(r), $"paste {id}.rtf through the OnRtbPasting replica", "05 §9 Q1", mac: false,
                 inputs: new JsonObject { ["rtf"] = "inputs/" + Path.GetFileName(file) });
            Done(r);
        }
    }

    // ---- W12: HtmlToXamlConverter raw output and the pasted result -------------------------------------------------
    /// <summary>The 05 §7.1 inputs, verbatim (H19 is the CF_HTML form).</summary>
    internal static readonly (string Id, string Html)[] Spec0571 =
    {
        ("H1", "<b>Hi</b>"),
        ("H2", "<p style=\"text-align:center;color:rgb(255,0,0)\">Hello <i>world</i></p>"),
        ("H3", "<ul><li>One</li><li>Two <b>bold</b></li></ul>"),
        ("H4", "<table><tr><th>A</th><th>B</th></tr><tr><td colspan=\"2\" style=\"text-align:right\">C</td></tr></table>"),
        ("H5", "a<br>b"),
        ("H6", "<h1>Title</h1>"),
        ("H7", "<p>a</p>\n<p>b</p>"),
        ("H8", "<span style=\"font-size:12pt;font-family:'Times New Roman'\">x</span>"),
        ("H9", "<a href=\"https://imo.org\" style=\"color:red\">IMO</a>"),
        ("H10", "<font color=\"#12\" size=\"5\">t</font>"),
        ("H11", "<p>a&nbsp;&nbsp;b</p>"),
        ("H12", "<table><tr><td>x<table><tr><td>y</td></tr></table></td></tr></table>"),
        ("H13", "<hr>"),
        ("H14", "<blockquote>q</blockquote>"),
        ("H15", "<script>x()</script><style>p{}</style><p>ok</p>"),
        ("H16", "<img src=\"a.png\"><p>t</p>"),
        ("H17", "<table></table>"),
        ("H18a", ""),
        ("H18b", "   "),
        ("H19", "Version:0.9\r\nStartHTML:00000097\r\nEndHTML:00000174\r\nStartFragment:00000131\r\nEndFragment:00000140\r\n<html><body>\r\n<!--StartFragment--><b>Hi</b><!--EndFragment-->\r\n</body></html>"),
        ("H20", "<pre>a   b</pre>"),
    };

    public static void W12()
    {
        var all = Spec0571.Select(x => (x.Id, x.Html, Source: "05 §7.1")).ToList();
        var inputs = Path.Combine(Out, "inputs");
        if (Directory.Exists(inputs))
            foreach (var file in Directory.GetFiles(inputs, "H-*.html").OrderBy(x => x, StringComparer.Ordinal))
                all.Add((Path.GetFileNameWithoutExtension(file), File.ReadAllText(file, Encoding.UTF8), "inputs/" + Path.GetFileName(file)));
        foreach (var (id, html, source) in all)
        {
            var converted = HtmlToXamlConverter.Convert(html);
            File.WriteAllText(Path.Combine(Out, $"W12-{id}.input.html"), html, new UTF8Encoding(false));
            Emit($"W12-{id}.converter", converted, $"HtmlToXamlConverter.Convert({source} {id})", "05 §7.1; K-12; K-13; S-7",
                 role: "converter", inputs: new JsonObject { ["html"] = html, ["source"] = source });

            var r = NewEditor();
            DataObject.AddPastingHandler(r, OnRtbPastingReplica);
            var data = new DataObject();
            data.SetData(DataFormats.Html, html);
            data.SetData(DataFormats.UnicodeText, "plain fallback");
            Clipboard.SetDataObject(data);
            r.Paste();
            Emit($"W12-{id}.pasted", Save(r), $"paste of {id} (Html + UnicodeText only)", "05 §7.1; K-12; K-13; S-7", mac: false,
                 inputs: new JsonObject { ["html"] = html });
            Done(r);
        }
    }

    // ---- W13: combined decorations; brush with opacity ---------------------------------------------------------------
    public static void W13()
    {
        const string S = "05 §9 Q1 combined decorations";
        var a = NewEditor(); TypeText(a, "both"); SelectAll(a);
        a.Selection.ApplyPropertyValue(Inline.TextDecorationsProperty, new TextDecorationCollection { TextDecorations.Underline[0], TextDecorations.Strikethrough[0] });
        Emit("W13a-underline-strike", Save(a), "TextDecorations = Underline[0] + Strikethrough[0]", S); Done(a);
        var b = NewEditor(); TypeText(b, "half"); SelectAll(b);
        b.Selection.ApplyPropertyValue(TextElement.ForegroundProperty, new SolidColorBrush(Color.FromArgb(255, 200, 0, 0)) { Opacity = 0.5 });
        Emit("W13b-brush-opacity", Save(b), "Foreground SolidColorBrush with Opacity 0.5", S); Done(b);
        var c = NewEditor(); TypeText(c, "over"); SelectAll(c);
        c.Selection.ApplyPropertyValue(Inline.TextDecorationsProperty, TextDecorations.OverLine);
        Emit("W13c-overline", Save(c), "TextDecorations.OverLine", S); Done(c);
        var d = NewEditor(); TypeText(d, "sup"); SelectAll(d);
        d.Selection.ApplyPropertyValue(Inline.BaselineAlignmentProperty, BaselineAlignment.Superscript);
        Emit("W13d-baseline-superscript", Save(d), "BaselineAlignment.Superscript", S); Done(d);
    }

    // ---- W14: embedded UI elements --------------------------------------------------------------------------------
    public static void W14()
    {
        var png = Convert.FromBase64String("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==");
        var bmp = new BitmapImage();
        bmp.BeginInit(); bmp.StreamSource = new MemoryStream(png); bmp.CacheOption = BitmapCacheOption.OnLoad; bmp.EndInit();
        var r = NewEditor(); r.Document.Blocks.Clear();
        var p = new Paragraph(new Run("before "));
        p.Inlines.Add(new InlineUIContainer(new Image { Source = bmp, Width = 1, Height = 1 }));
        p.Inlines.Add(new Run(" after"));
        r.Document.Blocks.Add(p);
        r.Document.Blocks.Add(new BlockUIContainer(new Button { Content = "x" }));
        Emit("W14-ui-containers", Save(r), "InlineUIContainer(Image) + BlockUIContainer(Button)", "05 CONT-038 (280)");
        Done(r);
    }

    // ---- W15: contextual properties on load / paste of a foreign-root section --------------------------------------
    public static void W15()
    {
        var segoe = $"<Section {NS} xml:space=\"preserve\" FontFamily=\"Segoe UI\" FontSize=\"13\" Foreground=\"#FF334155\"><Paragraph><Run>segoe body</Run></Paragraph></Section>";
        var a = NewEditor(); Load(a, segoe);
        Emit("W15a-load-segoe", Save(a), "Load an S-8-like Segoe section into the Consolas editor, save", "05 §4.3.1 (851)", inputs: new JsonObject { ["xaml"] = segoe }); Done(a);
        var b = NewEditor(); TypeText(b, "consolas ");
        Clipboard.SetDataObject(new DataObject(DataFormats.Xaml, segoe));
        b.Paste();
        Emit("W15b-paste-segoe", Save(b), "paste (clipboard Xaml) a Segoe-rooted section into a Consolas document", "05 §4.3.1 (851)", mac: false,
             inputs: new JsonObject { ["xaml"] = segoe }); Done(b);
    }

    // ---- W16: SIRE golden XAML ------------------------------------------------------------------------------------
    public static void W16()
    {
        var bankPath = Path.Combine(AppContext.BaseDirectory, "Data", "sire2_question_bank.json");
        var bank = JsonSerializer.Deserialize<QuestionBank>(File.ReadAllText(bankPath))!;
        foreach (var q in bank.Questions)                                   // SireBank.EnsureLoaded :49-61 steps
        {
            q.EvidenceTags = TagExtractor.ExtractTags(q);
            q.RoviqLocations = TagExtractor.ExtractRoviqLocations(q.RoviqSequence);
        }
        foreach (var number in new[] { "1.1.1", "2.1.1", "11.1.2" })
        {
            var q = bank.Questions.FirstOrDefault(x => x.QuestionNumber == number);
            if (q == null) { Console.WriteLine($"W16: question {number} not in the bank"); continue; }
            Emit($"W16-question-{number}", SireFlow.ToContainerXaml(SireFlow.BuildQuestion(q)),
                 $"SireToAa.BuildQuestionXaml({number}) = SireFlow.ToContainerXaml(SireFlow.BuildQuestion(q))", "12 Q-1 (834, 1421)", mac: false);
        }
        var qs = bank.Questions.Where(x => x.Section == "7.1").OrderBy(x => x.QuestionNumber, QuestionNumberComparer.Instance).ToList();
        Emit("W16-overview-7.1", SireFlow.ToContainerXaml(SireFlow.BuildOverview("SIRE Section 7.1", qs)),
             "SireToAa.BuildOverviewXaml(\"SIRE Section 7.1\", section 7.1)", "12 Q-1 (834, 1421)", mac: false);

        // An edited QuestionBodies entry: a RichTextBox configured like SirePage.xaml:169-174, then FlushBody :258-261.
        var first = bank.Questions.First(x => x.QuestionNumber == "1.1.1");
        var ink = new SolidColorBrush(Color.FromArgb(0xFF, 0x1A, 0x1A, 0x1A));
        var box = new RichTextBox
        {
            BorderThickness = new Thickness(0), Background = new SolidColorBrush(Color.FromArgb(0xFF, 0xFC, 0xFC, 0xFC)),
            Foreground = ink, FontFamily = new FontFamily("Segoe UI"), FontSize = 13, FontWeight = FontWeights.Normal,
            Padding = new Thickness(12), VerticalScrollBarVisibility = ScrollBarVisibility.Auto, AllowDrop = false,
        };
        new Window { Content = box, Width = 800, Height = 600, Left = -20000, Top = -20000, WindowStyle = WindowStyle.None,
                     ShowInTaskbar = false, ShowActivated = false }.Show();
        box.UpdateLayout();
        box.Document = SireFlow.BuildQuestion(first, Brushes.Black);
        var heading = box.Document.Blocks.OfType<Paragraph>().First();
        box.Selection.Select(heading.ContentEnd, heading.ContentEnd);
        EditingCommands.EnterParagraphBreak.Execute(null, box);
        EditingCommands.ToggleBold.Execute(null, box);
        TypeText(box, "note");
        var range = new TextRange(box.Document.ContentStart, box.Document.ContentEnd);
        using var ms = new MemoryStream();
        range.Save(ms, DataFormats.Xaml);
        Emit("W16-edited-body-1.1.1", Encoding.UTF8.GetString(ms.ToArray()), "edited QuestionBodies entry (SirePage.FlushBody)", "12 Q-1 (834, 1421)");
        Window.GetWindow(box)?.Close();
    }

    // ---- W17: lock sentinel round-trip --------------------------------------------------------------------------------
    public static void W17()
    {
        var r = NewEditor(); TypeText(r, "open locked open"); Select(r, "locked");
        r.Selection.ApplyPropertyValue(TextElement.BackgroundProperty, new SolidColorBrush(Color.FromArgb(0xFF, 0xFF, 0xE6, 0x99)));
        var first = Save(r); Emit("W17a-sentinel", first, "Background #FFFFE699 on a word", "05 §4.4"); Done(r);
        var b = NewEditor(); Load(b, first); var second = Save(b); Emit("W17b-sentinel-reload-1", second, "load + save once", "05 §4.4"); Done(b);
        var c = NewEditor(); Load(c, second); Emit("W17c-sentinel-reload-2", Save(c), "load + save twice", "05 §4.4"); Done(c);
    }

    // ---- W18: Clear formatting --------------------------------------------------------------------------------------
    public static void W18()
    {
        var r = NewEditor(); TypeText(r, "styled text"); SelectAll(r);
        EditingCommands.ToggleBold.Execute(null, r);
        r.Selection.ApplyPropertyValue(TextElement.ForegroundProperty, new SolidColorBrush(Colors.Red));
        r.Selection.ApplyPropertyValue(TextElement.BackgroundProperty, new SolidColorBrush(Colors.Yellow));
        EditingCommands.ToggleUnderline.Execute(null, r);
        Emit("W18a-before-clear", Save(r), "bold red highlighted underlined text", "05 CONT-028");
        SelectAll(r); ClearFormatting(r);
        Emit("W18b-cleared", Save(r), "ClearFormat_Click replica (Foreground reset to EditorFg #FF1A1A1A)", "05 CONT-028");
        Done(r);
    }
}
