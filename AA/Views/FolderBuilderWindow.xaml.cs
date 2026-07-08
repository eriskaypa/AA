using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using AA.Services;

namespace AA.Views;

public partial class FolderBuilderWindow : Window
{
    public FolderBuilderWindow()
    {
        InitializeComponent();
        BaseBox.Text = DataStore.FolderBuilderBase ?? "";
        RefreshPreview();
        Loaded += (_, _) => BulkBox.Focus();
    }

    private sealed class FolderNode
    {
        public string Name { get; set; } = "";
        public List<FolderNode> Children { get; } = new();
    }

    private void BulkBox_TextChanged(object sender, TextChangedEventArgs e) => RefreshPreview();

    private void RefreshPreview()
    {
        var (roots, rels) = Parse(BulkBox.Text);
        PreviewTree.ItemsSource = roots;
        PreviewHeader.Text = $"Preview ({rels.Count} folder{(rels.Count == 1 ? "" : "s")})";
    }

    /// <summary>Parse the bulk text into a folder tree (for preview) and a flat, parent-before-child
    /// list of relative paths (for creation). Indentation (Tab or 2 spaces) nests a line under the
    /// line above; a line may also contain '/' or '\' to create a nested path directly.</summary>
    private static (List<FolderNode> roots, List<string> rels) Parse(string? text)
    {
        var roots = new List<FolderNode>();
        var rels = new List<string>();
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        // stack of (depth, node, relPath) for the current ancestry
        var stack = new List<(int depth, FolderNode node, string rel)>();
        int lastDepth = -1;

        foreach (var raw in (text ?? "").Replace("\r\n", "\n").Split('\n'))
        {
            if (string.IsNullOrWhiteSpace(raw)) continue;

            int i = 0, spaces = 0, depth = 0;
            while (i < raw.Length && (raw[i] == ' ' || raw[i] == '\t'))
            {
                if (raw[i] == '\t') depth++; else spaces++;
                i++;
            }
            depth += spaces / 2;
            var name = raw.Substring(i).Trim();
            if (name.Length == 0) continue;
            if (depth > lastDepth + 1) depth = lastDepth + 1;

            var segments = name.Split('/', '\\').Select(Sanitize).Where(s => s.Length > 0).ToList();
            if (segments.Count == 0) continue;

            // Resolve the parent (the most recent line one level shallower).
            FolderNode? parentNode = null;
            string parentRel = "";
            if (depth > 0)
            {
                for (int k = stack.Count - 1; k >= 0; k--)
                    if (stack[k].depth == depth - 1) { parentNode = stack[k].node; parentRel = stack[k].rel; break; }
                if (parentNode == null) depth = 0;
            }

            // Build (or reuse) nodes for each path segment under the parent.
            var current = parentNode;
            var currentRel = parentRel;
            foreach (var seg in segments)
            {
                currentRel = string.IsNullOrEmpty(currentRel) ? seg : currentRel + "/" + seg;
                var siblings = current?.Children ?? roots;
                var existing = siblings.FirstOrDefault(c => string.Equals(c.Name, seg, StringComparison.OrdinalIgnoreCase));
                if (existing == null)
                {
                    existing = new FolderNode { Name = seg };
                    siblings.Add(existing);
                }
                if (seen.Add(currentRel)) rels.Add(currentRel);
                current = existing;
            }

            stack.RemoveAll(s => s.depth >= depth);
            stack.Add((depth, current!, currentRel));
            lastDepth = depth;
        }
        return (roots, rels);
    }

    private static string Sanitize(string s)
    {
        s = s.Trim();
        foreach (var c in Path.GetInvalidFileNameChars()) s = s.Replace(c, '_');
        return s.Trim().TrimEnd('.', ' ');
    }

    private void Browse_Click(object sender, RoutedEventArgs e)
    {
        var dlg = new System.Windows.Forms.FolderBrowserDialog { Description = "Choose the base location where folders will be created" };
        if (!string.IsNullOrWhiteSpace(BaseBox.Text) && Directory.Exists(BaseBox.Text)) dlg.SelectedPath = BaseBox.Text;
        if (dlg.ShowDialog() == System.Windows.Forms.DialogResult.OK)
        {
            BaseBox.Text = dlg.SelectedPath;
            DataStore.SetFolderBuilderBase(dlg.SelectedPath);
        }
    }

    private void Create_Click(object sender, RoutedEventArgs e)
    {
        var baseDir = BaseBox.Text?.Trim() ?? "";
        if (string.IsNullOrWhiteSpace(baseDir))
        {
            MessageBox.Show(this, "Choose a base location first (Browse...).", "Folder builder", MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }
        var (_, rels) = Parse(BulkBox.Text);
        if (rels.Count == 0)
        {
            StatusText.Text = "Nothing to create — type some folder names.";
            return;
        }

        if (!Directory.Exists(baseDir))
        {
            if (MessageBox.Show(this, $"The base location does not exist:\n{baseDir}\n\nCreate it?",
                    "Folder builder", MessageBoxButton.YesNo, MessageBoxImage.Question) != MessageBoxResult.Yes) return;
            try { Directory.CreateDirectory(baseDir); }
            catch (Exception ex) { MessageBox.Show(this, ex.Message, "Folder builder", MessageBoxButton.OK, MessageBoxImage.Error); return; }
        }

        if (MessageBox.Show(this, $"Create {rels.Count} folder{(rels.Count == 1 ? "" : "s")} under:\n{baseDir}?",
                "Confirm", MessageBoxButton.YesNo, MessageBoxImage.Question) != MessageBoxResult.Yes) return;

        int created = 0, existed = 0, failed = 0;
        foreach (var rel in rels)
        {
            try
            {
                var full = Path.Combine(baseDir, rel.Replace('/', Path.DirectorySeparatorChar));
                if (Directory.Exists(full)) existed++;
                else { Directory.CreateDirectory(full); created++; }
            }
            catch { failed++; }
        }

        DataStore.SetFolderBuilderBase(baseDir);
        StatusText.Text = $"Created {created}, already existed {existed}" + (failed > 0 ? $", failed {failed}" : "") + ".";
        if (created > 0 &&
            MessageBox.Show(this, $"Created {created} folder(s). Open the base location?", "Folder builder",
                MessageBoxButton.YesNo, MessageBoxImage.Information) == MessageBoxResult.Yes)
            OpenBase(baseDir);
    }

    private void OpenBase_Click(object sender, RoutedEventArgs e) => OpenBase(BaseBox.Text);

    private void OpenBase(string? dir)
    {
        if (string.IsNullOrWhiteSpace(dir) || !Directory.Exists(dir)) { StatusText.Text = "Base location not found."; return; }
        try { Process.Start(new ProcessStartInfo("explorer.exe", dir)); }
        catch (Exception ex) { MessageBox.Show(this, ex.Message, "Open failed", MessageBoxButton.OK, MessageBoxImage.Error); }
    }

    private void Clear_Click(object sender, RoutedEventArgs e) => BulkBox.Clear();

    private void Example_Click(object sender, RoutedEventArgs e)
    {
        BulkBox.Text =
            "Project A\n" +
            "\tDocuments\n" +
            "\tImages\n" +
            "\tReports\n" +
            "\t\t2026\n" +
            "Project B\n" +
            "\tDrawings\n" +
            "Shared/Templates\n";
    }

    private void Close_Click(object sender, RoutedEventArgs e) => Close();
}
