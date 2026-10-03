// WinCapture — Part 2 of the golden-fixture plan (spec 01 GF.6, DATA-321/322/325): the items that need WPF or
// Windows itself. Harness + W01–W06 follow the GF.6.4 snippet; W07–W18 (GF.6.5) live in Cases/Recipes.cs.
//
//   WinCapture all <outDir>                      every automated recipe (en-US), then the el-GR / th-TH invariance runs
//   WinCapture dump-clipboard <name> <inputsDir> records the clipboard's RTF/HTML/text/XAML formats (GF.6.6)
//   WinCapture load-check <macXamlDir> <outDir>  W23: WPF loads every Mac XAML output and re-saves it (GF.6.9)
using System.Diagnostics;
using System.Globalization;
using System.Reflection;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Documents;
using System.Windows.Input;
using System.Windows.Media;

namespace WinCapture;

internal static partial class Program
{
    internal static string Out = "";
    internal static readonly JsonSerializerOptions Meta = new() { WriteIndented = true, NewLine = "\n" };
    /// <summary>Case records of the current `all` run (GF.4.4 shape, family "xaml").</summary>
    internal static readonly List<JsonObject> Cases = new();
    /// <summary>When false (the culture invariance re-runs) Emit writes only the .xaml file.</summary>
    internal static bool Recording = true;

    [STAThread]
    private static int Main(string[] args)
    {
        if (args.Length < 2) { Console.Error.WriteLine("usage: WinCapture all <outDir> | dump-clipboard <name> <inputsDir> | load-check <macXamlDir> <outDir>"); return 2; }
        var culture = new CultureInfo("en-US");
        CultureInfo.DefaultThreadCurrentCulture = CultureInfo.DefaultThreadCurrentUICulture = culture;
        CultureInfo.CurrentCulture = CultureInfo.CurrentUICulture = culture;
        var app = new Application { ShutdownMode = ShutdownMode.OnExplicitShutdown };
        int rc = 0;
        app.Startup += (_, _) =>
        {
            try
            {
                rc = args[0] switch
                {
                    "all" => All(Directory.CreateDirectory(args[1]).FullName),
                    "dump-clipboard" => DumpClipboard(args[1], Directory.CreateDirectory(args[2]).FullName),
                    "load-check" => LoadCheck(args[1], Directory.CreateDirectory(args[2]).FullName),
                    _ => 2
                };
            }
            catch (Exception ex) { Console.Error.WriteLine(ex); rc = 1; }
            finally { app.Shutdown(); }
        };
        app.Run();
        return rc;
    }

    private static void RunRecipes()
    {
        W01(); W02(); W03(); W04(); W05(); W06();
        Recipes.W07(); Recipes.W08(); Recipes.W09(); Recipes.W10(); Recipes.W11(); Recipes.W12();
        Recipes.W13(); Recipes.W14(); Recipes.W15(); Recipes.W16(); Recipes.W17(); Recipes.W18();
    }

    private static int All(string outDir)
    {
        Out = outDir;
        Cases.Clear();
        Recording = true;
        RunRecipes();

        // Serializer invariance across cultures (GF.6.5 last row): the same recipes under el-GR and th-TH must
        // produce the same XAML as en-US.
        var invariance = new JsonArray();
        foreach (var name in new[] { "el-GR", "th-TH" })
        {
            var dir = Directory.CreateDirectory(Path.Combine(Path.GetTempPath(), "aa-wincapture-" + name + "-" + Guid.NewGuid().ToString("N"))).FullName;
            var c = new CultureInfo(name);
            CultureInfo.DefaultThreadCurrentCulture = CultureInfo.DefaultThreadCurrentUICulture = c;
            CultureInfo.CurrentCulture = CultureInfo.CurrentUICulture = c;
            Out = dir; Recording = false;
            try { RunRecipes(); }
            catch (Exception ex) { invariance.Add(new JsonObject { ["culture"] = name, ["error"] = ex.ToString() }); }
            foreach (var f in Directory.GetFiles(dir, "*.xaml").OrderBy(x => x, StringComparer.Ordinal))
            {
                var baseFile = Path.Combine(outDir, Path.GetFileName(f));
                var same = File.Exists(baseFile) && File.ReadAllBytes(baseFile).AsSpan().SequenceEqual(File.ReadAllBytes(f));
                invariance.Add(new JsonObject { ["culture"] = name, ["file"] = Path.GetFileName(f), ["identicalToEnUS"] = same });
            }
            try { Directory.Delete(dir, true); } catch { }
        }
        var en = new CultureInfo("en-US");
        CultureInfo.DefaultThreadCurrentCulture = CultureInfo.DefaultThreadCurrentUICulture = en;
        CultureInfo.CurrentCulture = CultureInfo.CurrentUICulture = en;
        Out = outDir; Recording = true;
        File.WriteAllText(Path.Combine(outDir, "culture-invariance.json"), invariance.ToJsonString(Meta) + "\n");

        var manifest = new JsonObject
        {
            ["schema"] = 1,
            ["generator"] = new JsonObject
            {
                ["name"] = "WinCapture", ["version"] = "1.0.0",
                ["linkedSources"] = Provenance(),
                ["runtime"] = System.Runtime.InteropServices.RuntimeInformation.FrameworkDescription,
                ["os"] = Environment.OSVersion.VersionString,
            },
            ["environment"] = JsonSerializer.SerializeToNode(Env()),
            ["generatedAtUtc"] = DateTime.UtcNow.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", CultureInfo.InvariantCulture),
            ["today"] = DateTime.Today.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture),
            ["runs"] = new JsonArray(new JsonObject
            {
                ["platform"] = "windows", ["timeZone"] = TimeZoneInfo.Local.Id, ["ianaTimeZone"] = IanaZone(), ["culture"] = "en-US",
            }),
            ["cases"] = new JsonArray(Cases.OrderBy(c => (string?)c["id"], StringComparer.Ordinal).Select(c => (JsonNode?)c).ToArray()),
            ["specConflicts"] = new JsonArray(),
            ["platformDivergences"] = new JsonArray(),
        };
        File.WriteAllText(Path.Combine(outDir, "MANIFEST.json"), manifest.ToJsonString(Meta) + "\n");
        Console.WriteLine($"WinCapture: {Cases.Count} capture(s) in {outDir}");
        return 0;
    }

    /// <summary>The capture machine's zone as an IANA id (the Mac's TimeZone cannot read Windows ids); the manual
    /// M-capture round trip falls back to it when manual\M-capture.timezone.txt is absent.</summary>
    private static string? IanaZone()
    {
        var local = TimeZoneInfo.Local;
        if (local.HasIanaId) return local.Id;
        return TimeZoneInfo.TryConvertWindowsIdToIanaId(local.Id, out var iana) ? iana : null;
    }

    /// <summary>SHA-256 of the linked files (DATA-301 provenance; a mismatch is reported, not fatal, so a capture
    /// on a machine with a CRLF checkout is visibly flagged).</summary>
    private static JsonArray Provenance()
    {
        var arr = new JsonArray();
        var dir = new DirectoryInfo(AppContext.BaseDirectory);
        while (dir != null && !(Directory.Exists(Path.Combine(dir.FullName, "AA")) && Directory.Exists(Path.Combine(dir.FullName, "mac")))) dir = dir.Parent;
        if (dir == null) return arr;
        var pins = new Dictionary<string, string>(StringComparer.Ordinal);
        var pinFile = Path.Combine(dir.FullName, "mac", "Docs", "original-source-checksums.sha256");
        if (File.Exists(pinFile))
            foreach (var line in File.ReadAllLines(pinFile))
                if (line.Length > 66) pins[line[66..]] = line[..64];
        foreach (var rel in new[] { "AA/Services/ListFormatting.cs", "AA/Services/HtmlToXamlConverter.cs", "AA/Sire/SireFlow.cs",
                                    "AA/Sire/SireModels.cs", "AA/Sire/TagExtractor.cs", "AA/Views/ContainerEditor.xaml.cs", "AA/App.xaml" })
        {
            var p = Path.Combine(dir.FullName, rel.Replace('/', Path.DirectorySeparatorChar));
            if (!File.Exists(p)) continue;
            using var s = File.OpenRead(p);
            var hash = Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(s)).ToLowerInvariant();
            arr.Add(new JsonObject { ["path"] = rel, ["sha256"] = hash, ["matchesPin"] = pins.TryGetValue(rel, out var pin) && pin == hash });
        }
        return arr;
    }

    // ---- the editor, configured exactly like ContainerEditor.xaml:59-63 + App.xaml:37-40 -----------------------------
    internal static RichTextBox NewEditor()
    {
        var ink = new SolidColorBrush(Color.FromArgb(0xFF, 0x1A, 0x1A, 0x1A));          // EditorFg
        var rtb = new RichTextBox
        {
            AcceptsTab = true, BorderThickness = new Thickness(0), Padding = new Thickness(8),
            Background = new SolidColorBrush(Color.FromArgb(0xFF, 0xFC, 0xFC, 0xFC)),     // EditorBg
            Foreground = ink, CaretBrush = ink,
            FontFamily = new FontFamily("Consolas"), FontSize = 14,                       // MainFont, 14
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto
        };
        SpellCheck.SetIsEnabled(rtb, true);
        // Hosted in a real, shown, off-screen window so templates and the TextEditor attach as in the app.
        new Window { Content = rtb, Width = 800, Height = 600, Left = -20000, Top = -20000,
                     WindowStyle = WindowStyle.None, ShowInTaskbar = false, ShowActivated = false }.Show();
        rtb.UpdateLayout();
        return rtb;
    }
    internal static void Done(RichTextBox rtb) => Window.GetWindow(rtb)?.Close();

    internal static string Save(FlowDocument d)                                   // ContainerEditor.PersistRichText :461-464
    {
        var range = new TextRange(d.ContentStart, d.ContentEnd);
        using var ms = new MemoryStream();
        range.Save(ms, DataFormats.Xaml);
        return Encoding.UTF8.GetString(ms.ToArray());
    }
    internal static string Save(RichTextBox rtb) => Save(rtb.Document);

    internal static void Load(RichTextBox rtb, string xaml)                       // ContainerEditor.Load :425-429
    {
        using var ms = new MemoryStream(Encoding.UTF8.GetBytes(xaml));
        new TextRange(rtb.Document.ContentStart, rtb.Document.ContentEnd).Load(ms, DataFormats.Xaml);
    }

    // Programmatic typing: replace the collapsed selection and collapse after it (what TextEditor does for typed
    // text, minus input-language stamping, which M-06 captures by hand).
    internal static void TypeText(RichTextBox rtb, string text)
    {
        rtb.Selection.Text = text;
        rtb.Selection.Select(rtb.Selection.End, rtb.Selection.End);
    }
    internal static TextRange Find(FlowDocument d, string needle)                 // needle must lie inside one Run
    {
        for (var p = d.ContentStart; p != null; p = p.GetNextContextPosition(LogicalDirection.Forward))
            if (p.GetPointerContext(LogicalDirection.Forward) == TextPointerContext.Text)
            {
                int i = p.GetTextInRun(LogicalDirection.Forward).IndexOf(needle, StringComparison.Ordinal);
                if (i >= 0) { var s = p.GetPositionAtOffset(i)!; return new TextRange(s, s.GetPositionAtOffset(needle.Length)!); }
            }
        throw new InvalidOperationException("not found: " + needle);
    }
    internal static void Select(RichTextBox rtb, string needle) { var r = Find(rtb.Document, needle); rtb.Selection.Select(r.Start, r.End); }

    /// <summary>Writes `<id>.xaml` (UTF-8, no BOM), `<id>.json-string.txt` (as inside data.json) and `<id>.meta.json`,
    /// and records the case. <paramref name="settles"/> names the spec marker; <paramref name="mac"/> false = the
    /// Mac does not reproduce this capture (e.g. it documents a Windows editing command the Mac re-implements).</summary>
    internal static void Emit(string id, string xaml, string what, string settles = "", bool mac = true,
                              string role = "xaml", JsonObject? inputs = null, string normative = "must")
    {
        File.WriteAllBytes(Path.Combine(Out, id + ".xaml"), new UTF8Encoding(false).GetBytes(xaml));
        if (!Recording) return;
        File.WriteAllText(Path.Combine(Out, id + ".json-string.txt"), JsonSerializer.Serialize(xaml)); // as inside data.json
        File.WriteAllText(Path.Combine(Out, id + ".meta.json"),
            JsonSerializer.Serialize(new { id, what, culture = CultureInfo.CurrentCulture.Name }, Meta));
        var output = new JsonObject { ["role"] = role, ["file"] = id + ".xaml" };
        if (!mac) output["mac"] = false;
        Cases.Add(new JsonObject
        {
            ["id"] = id, ["family"] = "xaml", ["title"] = what, ["platform"] = "windows", ["tz"] = TimeZoneInfo.Local.Id,
            ["normative"] = normative, ["compare"] = "xml-canonical", ["dependsOnToday"] = false,
            ["inputs"] = inputs ?? new JsonObject(),
            ["outputs"] = new JsonArray(output),
            ["macExpectation"] = new JsonObject { ["kind"] = "same" },
            ["settles"] = new JsonArray(settles.Split(';', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
                                               .Select(s => (JsonNode?)s).ToArray()),
        });
    }

    /// <summary>Records a non-XAML capture (gestures, undo state) as a record-only JSON case.</summary>
    internal static void EmitJson(string id, JsonNode node, string what, string settles)
    {
        File.WriteAllText(Path.Combine(Out, id + ".json"), node.ToJsonString(Meta) + "\n");
        if (!Recording) return;
        Cases.Add(new JsonObject
        {
            ["id"] = id, ["family"] = "xaml", ["title"] = what, ["platform"] = "windows", ["tz"] = TimeZoneInfo.Local.Id,
            ["normative"] = "record-only", ["compare"] = "json-semantic", ["dependsOnToday"] = false, ["inputs"] = new JsonObject(),
            ["outputs"] = new JsonArray(new JsonObject { ["role"] = "result", ["file"] = id + ".json", ["mac"] = false }),
            ["macExpectation"] = new JsonObject { ["kind"] = "same" },
            ["settles"] = new JsonArray((JsonNode?)settles),
        });
    }

    // ---- W01: root attribute set + S-1 body built through the toolbar code paths ----------------------------
    private static void W01()
    {
        var p = NewEditor(); Emit("W01a-pristine", Save(p), "new editor, never touched", "05 §4.3.4 S-1; 03 Q-9"); Done(p);
        var rtb = NewEditor();
        TypeText(rtb, "Check the main engine oil level.");
        EditingCommands.EnterParagraphBreak.Execute(null, rtb);
        TypeText(rtb, "Urgent");
        Select(rtb, "main engine"); EditingCommands.ToggleBold.Execute(null, rtb);                    // Bold_Click :588
        Select(rtb, "Urgent");
        EditingCommands.AlignCenter.Execute(null, rtb);                                               // :616
        rtb.Selection.ApplyPropertyValue(TextElement.ForegroundProperty,
            new SolidColorBrush(Color.FromArgb(255, 255, 0, 0)));                                     // Color_Click :597-605
        rtb.Selection.ApplyPropertyValue(TextElement.BackgroundProperty,
            new SolidColorBrush(Color.FromArgb(255, 255, 255, 0)));                                   // Highlight_Click :606-614
        EditingCommands.ToggleUnderline.Execute(null, rtb);                                           // :590
        var x = Save(rtb); Emit("W01b-S1-typed", x, "S-1 through toolbar paths", "05 §4.3.4 S-1; 03 Q-9; 03:1221"); Done(rtb);
        var again = NewEditor(); Load(again, x); Emit("W01c-S1-load-save", Save(again), "load(W01b) then save", "05 §4.3.4 S-1"); Done(again);
    }

    // ---- W02: verbatim body of ContainerEditor.InsertTable_Click :727-768 (dialog → literal value) ------------
    private static readonly Brush TableBorder = new SolidColorBrush(Color.FromRgb(0x9A, 0xA0, 0xA6));       // :725
    private static void InsertTable(RichTextBox Rtb, string value)
    {
        var m = Regex.Match(value ?? "", @"^\s*(\d+)\s*[xX*]\s*(\d+)\s*$");
        int rows = m.Success ? Math.Clamp(int.Parse(m.Groups[1].Value), 1, 50) : 3;
        int cols = m.Success ? Math.Clamp(int.Parse(m.Groups[2].Value), 1, 20) : 3;
        var table = new Table { CellSpacing = 0, Margin = new Thickness(0, 4, 0, 4) };
        for (int c = 0; c < cols; c++) table.Columns.Add(new TableColumn());
        var rg = new TableRowGroup();
        for (int r = 0; r < rows; r++)
        {
            var tr = new TableRow();
            for (int c = 0; c < cols; c++)
            {
                var cell = new TableCell(new Paragraph(new Run("")))
                    { BorderBrush = TableBorder, BorderThickness = new Thickness(0.6), Padding = new Thickness(3, 1, 3, 1) };
                if (r == 0) cell.FontWeight = FontWeights.Bold;
                tr.Cells.Add(cell);
            }
            rg.Rows.Add(tr);
        }
        table.RowGroups.Add(rg);
        var caretBlock = Rtb.CaretPosition?.Paragraph as Block;
        if (caretBlock != null && ReferenceEquals(caretBlock.Parent, Rtb.Document)) Rtb.Document.Blocks.InsertAfter(caretBlock, table);
        else Rtb.Document.Blocks.Add(table);
        Rtb.CaretPosition = table.RowGroups[0].Rows[0].Cells[0].ContentStart;
    }
    private static void W02()
    {
        foreach (var (id, size, prep) in new (string, string, Action<RichTextBox>)[] {
            ("W02a-2x2-after-para", "2x2",   r => TypeText(r, "Before table")),
            ("W02b-3x4",            "3x4",   r => TypeText(r, "x")),
            ("W02c-junk-3x3",       "junk",  r => TypeText(r, "x")),
            ("W02d-0x0-clamped",    "0x0",   r => TypeText(r, "x")),
            ("W02e-60x30-clamped",  "60x30", r => TypeText(r, "x")),
            ("W02f-empty-doc",      "2x2",   r => r.Document.Blocks.Clear()) })
        {
            var rtb = NewEditor(); prep(rtb); InsertTable(rtb, size);
            Emit(id, Save(rtb), "InsertTable " + size, "05 S-4 (947)", inputs: new JsonObject { ["size"] = size }); Done(rtb);
        }
    }

    // ---- W03: verbatim body of InsertLink_Click :704-723 (RequestNavigate handler omitted: never serialized) --
    private static void InsertLink(RichTextBox Rtb, string value)
    {
        if (!Uri.TryCreate(value, UriKind.Absolute, out var uri)) return;
        if (Rtb.Selection.IsEmpty)
        {
            var run = new Run(uri.ToString());
            Rtb.CaretPosition.Paragraph?.Inlines.Add(new Hyperlink(run) { NavigateUri = uri });
        }
        else _ = new Hyperlink(Rtb.Selection.Start, Rtb.Selection.End) { NavigateUri = uri };
    }
    private static void W03()
    {
        var a = NewEditor(); TypeText(a, "See "); InsertLink(a, "https://www.imo.org"); Emit("W03a-empty-selection", Save(a), "append to caret paragraph", "05 S-5"); Done(a);
        var b = NewEditor(); TypeText(b, "Read the IMO page"); Select(b, "IMO"); InsertLink(b, "https://www.imo.org"); Emit("W03b-wrap-selection", Save(b), "wrap", "05 S-5"); Done(b);
        var c = NewEditor(); TypeText(c, "x "); InsertLink(c, "https://example.com/a b/ü?q=1&r=2"); Emit("W03c-escaping", Save(c), "space, non-ASCII, &", "05 S-5"); Done(c);
        var d = NewEditor(); TypeText(d, "Mail "); InsertLink(d, "mailto:ops@ship.test"); Emit("W03d-mailto", Save(d), "mailto", "05 S-5"); Done(d);
    }

    // ---- W04: Ctrl+= / Ctrl+Shift+= commands ----------------------------------------------------------------
    private static void W04()
    {
        var a = NewEditor(); TypeText(a, "H2O and m2");
        var h2o = Find(a.Document, "H2O"); a.Selection.Select(h2o.Start.GetPositionAtOffset(1)!, h2o.Start.GetPositionAtOffset(2)!);
        EditingCommands.ToggleSubscript.Execute(null, a); Emit("W04a-subscript", Save(a), "ToggleSubscript on 2 of H2O", "05 S-9 (972)");
        EditingCommands.ToggleSubscript.Execute(null, a); Emit("W04b-subscript-off", Save(a), "toggled back", "05 S-9 (972)");
        var m2 = Find(a.Document, "m2"); a.Selection.Select(m2.Start.GetPositionAtOffset(1)!, m2.End);
        EditingCommands.ToggleSuperscript.Execute(null, a); Emit("W04c-superscript", Save(a), "ToggleSuperscript on 2 of m2", "05 S-9 (972)"); Done(a);
    }

    // ---- W05: every way a note becomes empty ------------------------------------------------------------------
    private static void W05()
    {
        var a = NewEditor(); TypeText(a, "x"); a.SelectAll(); EditingCommands.Delete.Execute(null, a);
        Emit("W05a-typed-then-deleted", Save(a), "type x, select all, Delete", "05 S-10 (974); 05 §9 Q6"); Done(a);
        var b = NewEditor(); Load(b, File.ReadAllText(Path.Combine(Out, "W01b-S1-typed.xaml"))); b.SelectAll();
        EditingCommands.Delete.Execute(null, b); Emit("W05b-rich-then-deleted", Save(b), "S-1 then delete all", "05 S-10 (974)"); Done(b);
        var c = NewEditor(); c.Document.Blocks.Clear();
        Emit("W05c-blocks-cleared", Save(c), "ContainerEditor.Load with empty body (:439-442), then a save", "05 S-10 (974); 05 §9 Q6"); Done(c);
        // Does WPF load "" (the Mac's empty-note form, DECISIONS 05) and save an equivalent? (GF.6.10)
        var d = NewEditor();
        string verdict;
        try { Load(d, ""); verdict = "loaded"; } catch (Exception ex) { verdict = "threw " + ex.GetType().FullName; }
        Emit("W05d-load-empty-string", Save(d), "TextRange.Load(\"\") then save — " + verdict, "05 §9 Q6", inputs: new JsonObject { ["load"] = verdict });
        Done(d);
    }

    // ---- W06: the built-in key map, read from WPF's class input bindings (WPF-internal field; read-only) -----
    private static void W06()
    {
        Done(NewEditor());   // RichTextBox static ctor has registered TextEditor's class bindings
        var rows = new JsonArray();
        var f = typeof(CommandManager).GetField("_classInputBindings", BindingFlags.NonPublic | BindingFlags.Static);
        if (f?.GetValue(null) is System.Collections.IDictionary map)
            foreach (var t in new[] { typeof(RichTextBox), typeof(System.Windows.Controls.Primitives.TextBoxBase), typeof(Control), typeof(UIElement) })
                if (map[t] is InputBindingCollection ibc)
                    foreach (InputBinding ib in ibc)
                        if (ib.Gesture is KeyGesture kg)
                            rows.Add(new JsonObject
                            {
                                ["owner"] = t.Name, ["command"] = (ib.Command as RoutedCommand)?.Name,
                                ["key"] = kg.Key.ToString(), ["modifiers"] = kg.Modifiers.ToString(),
                                ["display"] = kg.GetDisplayStringForCulture(CultureInfo.InvariantCulture),
                            });
        foreach (var cmd in new[] { ApplicationCommands.Undo, ApplicationCommands.Redo, ApplicationCommands.Cut,
                                    ApplicationCommands.Copy, ApplicationCommands.Paste, ApplicationCommands.SelectAll })
            foreach (InputGesture g in cmd.InputGestures)
                if (g is KeyGesture kg) rows.Add(new JsonObject
                {
                    ["owner"] = "ApplicationCommands", ["command"] = cmd.Name,
                    ["key"] = kg.Key.ToString(), ["modifiers"] = kg.Modifiers.ToString(), ["display"] = kg.DisplayString,
                });
        // If the field is absent in the installed WPF, rows is empty: run the manual M-09 keyboard check instead.
        EmitJson("W06-gestures", rows, "built-in RichTextBox key map (CommandManager class input bindings)", "05 CONT-030 (214)");
    }

    // ---- clipboard capture (GF.6.6) and reverse load-check (W23) ---------------------------------------------
    private static int DumpClipboard(string name, string dir)
    {
        var d = Clipboard.GetDataObject();
        File.WriteAllText(Path.Combine(dir, name + ".formats.json"), JsonSerializer.Serialize(d.GetFormats(false), Meta));
        foreach (var (fmt, ext) in new[] { (DataFormats.Rtf, "rtf"), (DataFormats.Html, "html"), (DataFormats.UnicodeText, "txt"), (DataFormats.Xaml, "xaml") })
            if (d.GetDataPresent(fmt) && d.GetData(fmt) is string s)
                File.WriteAllBytes(Path.Combine(dir, $"{name}.{ext}"), new UTF8Encoding(false).GetBytes(s));
        Console.WriteLine($"dump-clipboard: {name} → {dir} ({string.Join(", ", d.GetFormats(false))})");
        return 0;
    }

    private static int LoadCheck(string macDir, string outDir)
    {
        var results = new List<(string name, bool ok, string detail)>();
        foreach (var file in Directory.GetFiles(macDir, "*.xaml").OrderBy(x => x, StringComparer.Ordinal))
        {
            var name = Path.GetFileNameWithoutExtension(file);
            var rtb = NewEditor();
            try
            {
                Load(rtb, File.ReadAllText(file, new UTF8Encoding(false)));
                File.WriteAllBytes(Path.Combine(outDir, name + ".wpf-resaved.xaml"), new UTF8Encoding(false).GetBytes(Save(rtb)));
                results.Add((name, true, new TextRange(rtb.Document.ContentStart, rtb.Document.ContentEnd).Text));
            }
            catch (Exception ex) { results.Add((name, false, ex.GetType().FullName + ": " + ex.Message)); }
            finally { Done(rtb); }
        }
        File.WriteAllText(Path.Combine(outDir, "load-check.json"),
            JsonSerializer.Serialize(results.Select(r => new { r.name, r.ok, r.detail }), Meta) + "\n");
        Console.WriteLine($"load-check: {results.Count} file(s), {results.Count(r => !r.ok)} failure(s)");
        return results.All(r => r.ok) && results.Count > 0 ? 0 : 1;
    }

    private static object Env() => new
    {
        os = Environment.OSVersion.VersionString,
        dotnet = System.Runtime.InteropServices.RuntimeInformation.FrameworkDescription,
        presentationFramework = FileVersionInfo.GetVersionInfo(typeof(FrameworkElement).Assembly.Location).FileVersion,
        culture = CultureInfo.CurrentCulture.Name,
        inputLanguage = InputLanguageManager.Current.CurrentInputLanguage?.Name,
        consolasInstalled = Fonts.SystemFontFamilies.Any(f => f.Source == "Consolas"),
        displayScale = PresentationSource.FromVisual(Application.Current.MainWindow ?? new Window())?.CompositionTarget?.TransformToDevice.M11,
        capturedUtc = DateTime.UtcNow.ToString("O", CultureInfo.InvariantCulture)
    };
}
