using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Media;
using System.Text;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Documents;
using System.Windows.Input;
using System.Windows.Media;
using AA.Models;
using AA.Services;
using Microsoft.Win32;

namespace AA.Views;

public partial class ContainerEditor : UserControl
{
    private Container? _container;
    private AppRepository? _repo;
    /// <summary>All containers (so linked containers can share their files via combined view, optional).</summary>
    private List<FileItem> _clipboard = new();
    private bool _cutMode;
    private bool _loading;
    /// <summary>True only when the current document actually contains locked text — lets the
    /// per-keystroke lock filtering short-circuit entirely (0 overhead) in the common case.</summary>
    private bool _hasAnyLock;
    private readonly System.Windows.Threading.DispatcherTimer _rtbDebounce;

    /// <summary>System font list, enumerated + sorted ONCE (shared by every editor instance).</summary>
    private static readonly string[] FontFamilies =
        Fonts.SystemFontFamilies.Select(f => f.Source).OrderBy(s => s, StringComparer.OrdinalIgnoreCase).ToArray();

    public ContainerEditor()
    {
        InitializeComponent();
        FontFamilyBox.ItemsSource = FontFamilies;
        FontFamilyBox.SelectedItem = "Consolas";
        FontSizeBox.ItemsSource = new[] { "8","9","10","11","12","14","16","18","20","24","28","32","36","48","72" };
        FontSizeBox.SelectedItem = "14";

        _rtbDebounce = new System.Windows.Threading.DispatcherTimer { Interval = TimeSpan.FromMilliseconds(400) };
        _rtbDebounce.Tick += (_, _) => { _rtbDebounce.Stop(); PersistRichText(); };

        Rtb.SelectionChanged += (_, _) => SyncToolbarFromSelection();
        Rtb.TextChanged += (_, _) =>
        {
            if (_loading) return;
            _rtbDebounce.Stop();
            _rtbDebounce.Start();
        };

        // Convert HTML clipboard payloads (from browsers / web pages) into FlowDocument
        // XAML before WPF pastes them. Native Xaml / Rtf are still handled by WPF.
        DataObject.AddPastingHandler(Rtb, OnRtbPasting);

        // Per-selection edit lock filtering.
        Rtb.PreviewKeyDown += Rtb_PreviewKeyDown;
        Rtb.PreviewTextInput += Rtb_PreviewTextInput;
        CommandManager.AddPreviewExecutedHandler(Rtb, Rtb_PreviewExecuted);
    }

    private void OnRtbPasting(object sender, DataObjectPastingEventArgs e)
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

    public void Load(Container c, AppRepository? repo = null)
    {
        // Flush any pending edits from the previous container before switching.
        if (!_loading && _rtbDebounce.IsEnabled)
        {
            _rtbDebounce.Stop();
            PersistRichText();
        }
        _loading = true;
        _container = c;
        _repo = repo;

        string? toShow = c.RichTextXaml;

        // Back-compat: legacy whole-document encryption is no longer used. If we encounter an
        // encrypted blob, try to silently decrypt and migrate to plaintext in-place.
        if (PasswordService.IsEncrypted(toShow))
        {
            if (PasswordService.IsUnlocked)
            {
                toShow = PasswordService.Decrypt(c.RichTextXaml!) ?? "";
                c.RichTextXaml = toShow;
                c.IsLocked = false;
                _repo?.MarkDirty();
            }
            else
            {
                // Leave the blob in storage; render an empty document and let the user unlock later.
                toShow = "";
            }
        }
        c.IsLocked = false;

        if (!string.IsNullOrWhiteSpace(toShow))
        {
            try
            {
                var bytes = Encoding.UTF8.GetBytes(toShow);
                using var ms = new MemoryStream(bytes);
                var range = new TextRange(Rtb.Document.ContentStart, Rtb.Document.ContentEnd);
                range.Load(ms, DataFormats.Xaml);
            }
            catch
            {
                Rtb.Document.Blocks.Clear();
                Rtb.Document.Blocks.Add(new Paragraph(new Run(toShow)));
            }
        }
        else
        {
            Rtb.Document.Blocks.Clear();
        }

        // Does this document actually carry any locked runs? If not, the per-keystroke lock
        // filtering is skipped entirely. Computed by walking the loaded document (accurate) rather
        // than substring-scanning the XAML, which false-positived on gold foreground/highlight colours.
        _hasAnyLock = DocumentContainsLock();

        RefreshFileLists();
        _loading = false;
    }

    private void PersistRichText()
    {
        if (_container == null) return;
        var range = new TextRange(Rtb.Document.ContentStart, Rtb.Document.ContentEnd);
        using var ms = new MemoryStream();
        range.Save(ms, DataFormats.Xaml);
        _container.RichTextXaml = Encoding.UTF8.GetString(ms.ToArray());
        _repo?.MarkDirty();
    }

    /// <summary>Force any buffered rich-text changes to be written immediately.</summary>
    public void FlushPending()
    {
        if (_rtbDebounce.IsEnabled)
        {
            _rtbDebounce.Stop();
            PersistRichText();
        }
    }

    private void RefreshFileLists()
    {
        if (_container == null) return;
        LvAll.ItemsSource = _container.Files;
        LvDocs.ItemsSource = _container.Files.Where(f => f.Kind == FileKind.Document).ToList();
        LvImages.ItemsSource = _container.Files.Where(f => f.Kind == FileKind.Image).ToList();
        LvVideos.ItemsSource = _container.Files.Where(f => f.Kind == FileKind.Video).ToList();
        LvLinks.ItemsSource = _container.Files.Where(f => f.IsLink).ToList();
        LvOther.ItemsSource = _container.Files.Where(f => f.Kind == FileKind.Other && !f.IsLink).ToList();
        foreach (var lv in new[] { LvAll, LvDocs, LvImages, LvVideos, LvLinks, LvOther })
            EnsureFileContextMenu(lv);
    }

    private void EnsureFileContextMenu(ListView lv)
    {
        if (lv.ContextMenu != null) return;
        var cm = new ContextMenu();
        var open = new MenuItem { Header = "Open" };
        open.Click += (_, _) => OpenSelected();
        var folder = new MenuItem { Header = "Open containing folder" };
        folder.Click += (_, _) => OpenContainingFolder();
        var rename = new MenuItem { Header = "Rename..." };
        rename.Click += (_, _) => RenameSelected();
        var link = new MenuItem { Header = "Link to items..." };
        link.Click += (_, _) => LinkSelectedToItems();
        var remove = new MenuItem { Header = "Remove" };
        remove.Click += (_, _) => { RemoveFile_Click(this, new RoutedEventArgs()); };
        cm.Items.Add(open);
        cm.Items.Add(folder);
        cm.Items.Add(rename);
        cm.Items.Add(link);
        cm.Items.Add(new Separator());
        cm.Items.Add(remove);
        lv.ContextMenu = cm;
    }

    private void OpenContainingFolder()
    {
        var lv = CurrentLv(); if (lv?.SelectedItem is not FileItem fi) return;
        try
        {
            if (fi.IsLink) { Process.Start(new ProcessStartInfo(fi.Path) { UseShellExecute = true }); return; }
            var abs = DataStore.ResolveFilePath(fi.Path);
            if (File.Exists(abs))
                Process.Start(new ProcessStartInfo("explorer.exe", $"/select,\"{abs}\""));
            else
                MessageBox.Show($"File not found:\n{abs}", "Open folder");
        }
        catch (Exception ex) { MessageBox.Show(ex.Message, "Open folder failed"); }
    }

    private void RenameSelected()
    {
        var lv = CurrentLv(); if (lv?.SelectedItem is not FileItem fi) return;
        var p = new PromptWindow("Rename", "New name:", fi.Name) { Owner = Window.GetWindow(this) };
        if (p.ShowDialog() == true && !string.IsNullOrWhiteSpace(p.Value))
        {
            fi.Name = p.Value;
            _repo?.MarkDirty();
            RefreshFileLists();
        }
    }

    private void LinkSelectedToItems()
    {
        if (_repo == null) return;
        var lv = CurrentLv(); if (lv?.SelectedItem is not FileItem fi) return;
        static int KindOrder(AA.Models.ItemKind k) => k switch
        {
            AA.Models.ItemKind.Equipment => 0,
            AA.Models.ItemKind.Task => 1,
            AA.Models.ItemKind.Procedure => 2,
            AA.Models.ItemKind.Vessel => 3,
            _ => 99
        };
        var candidates = _repo.AllItems()
            .OrderBy(i => KindOrder(i.Kind))
            .ThenBy(i => i.Name, StringComparer.OrdinalIgnoreCase)
            .Select(i => new PickerItem { Display = $"[{i.Kind}] {i.Name}", Tag = (object)i.Id });
        var dlg = new ItemPickerWindow($"Link '{fi.Name}' to items", candidates, fi.LinkedItemIds.Cast<object>())
        { Owner = Window.GetWindow(this) };
        if (dlg.ShowDialog() == true)
        {
            fi.LinkedItemIds.Clear();
            foreach (var id in dlg.SelectedTags.Cast<Guid>()) fi.LinkedItemIds.Add(id);
            _repo.MarkDirty();
        }
    }

    // ---- Toolbar handlers ----
    private void SyncToolbarFromSelection()
    {
        var ff = Rtb.Selection.GetPropertyValue(TextElement.FontFamilyProperty);
        if (ff is FontFamily fam) FontFamilyBox.SelectedItem = fam.Source;
        var fs = Rtb.Selection.GetPropertyValue(TextElement.FontSizeProperty);
        if (fs is double d) FontSizeBox.Text = d.ToString();
    }
    private void FontFamily_Changed(object sender, SelectionChangedEventArgs e)
    {
        if (FontFamilyBox.SelectedItem is string name)
            Rtb.Selection.ApplyPropertyValue(TextElement.FontFamilyProperty, new FontFamily(name));
        Rtb.Focus();
    }
    private void FontSize_Changed(object sender, SelectionChangedEventArgs e) => ApplyFontSize();
    private void FontSize_TextChanged(object sender, RoutedEventArgs e) => ApplyFontSize();
    private void ApplyFontSize()
    {
        if (double.TryParse(FontSizeBox.Text, out var size) && size > 0)
            Rtb.Selection.ApplyPropertyValue(TextElement.FontSizeProperty, size);
    }
    private void Bold_Click(object s, RoutedEventArgs e) => EditingCommands.ToggleBold.Execute(null, Rtb);
    private void Italic_Click(object s, RoutedEventArgs e) => EditingCommands.ToggleItalic.Execute(null, Rtb);
    private void Underline_Click(object s, RoutedEventArgs e) => EditingCommands.ToggleUnderline.Execute(null, Rtb);
    private void Strike_Click(object s, RoutedEventArgs e)
    {
        var cur = Rtb.Selection.GetPropertyValue(Inline.TextDecorationsProperty) as TextDecorationCollection;
        Rtb.Selection.ApplyPropertyValue(Inline.TextDecorationsProperty,
            cur != null && cur.Count > 0 && cur[0] == TextDecorations.Strikethrough[0] ? null : TextDecorations.Strikethrough);
    }
    private void Color_Click(object s, RoutedEventArgs e)
    {
        var dlg = new System.Windows.Forms.ColorDialog();
        if (dlg.ShowDialog() == System.Windows.Forms.DialogResult.OK)
        {
            var b = new SolidColorBrush(Color.FromArgb(dlg.Color.A, dlg.Color.R, dlg.Color.G, dlg.Color.B));
            Rtb.Selection.ApplyPropertyValue(TextElement.ForegroundProperty, b);
        }
    }
    private void Highlight_Click(object s, RoutedEventArgs e)
    {
        var dlg = new System.Windows.Forms.ColorDialog();
        if (dlg.ShowDialog() == System.Windows.Forms.DialogResult.OK)
        {
            var b = new SolidColorBrush(Color.FromArgb(dlg.Color.A, dlg.Color.R, dlg.Color.G, dlg.Color.B));
            Rtb.Selection.ApplyPropertyValue(TextElement.BackgroundProperty, b);
        }
    }
    private void AlignLeft_Click(object s, RoutedEventArgs e) => EditingCommands.AlignLeft.Execute(null, Rtb);
    private void AlignCenter_Click(object s, RoutedEventArgs e) => EditingCommands.AlignCenter.Execute(null, Rtb);
    private void AlignRight_Click(object s, RoutedEventArgs e) => EditingCommands.AlignRight.Execute(null, Rtb);
    private void AlignJustify_Click(object s, RoutedEventArgs e) => EditingCommands.AlignJustify.Execute(null, Rtb);
    private void Bullets_Click(object s, RoutedEventArgs e) => EditingCommands.ToggleBullets.Execute(null, Rtb);
    private void Numbers_Click(object s, RoutedEventArgs e) => EditingCommands.ToggleNumbering.Execute(null, Rtb);
    private void Indent_Click(object s, RoutedEventArgs e) => EditingCommands.IncreaseIndentation.Execute(null, Rtb);
    private void Outdent_Click(object s, RoutedEventArgs e) => EditingCommands.DecreaseIndentation.Execute(null, Rtb);
    private void Undo_Click(object s, RoutedEventArgs e) => Rtb.Undo();
    private void Redo_Click(object s, RoutedEventArgs e) => Rtb.Redo();
    private void ClearFormat_Click(object s, RoutedEventArgs e)
    {
        var sel = Rtb.Selection;
        sel.ApplyPropertyValue(TextElement.FontWeightProperty, FontWeights.Normal);
        sel.ApplyPropertyValue(TextElement.FontStyleProperty, FontStyles.Normal);
        sel.ApplyPropertyValue(Inline.TextDecorationsProperty, null);
        // Reset to the editor "paper" text colour (always dark/readable), not the themed Fg
        // which is light in dark mode and would be invisible on the light document surface.
        sel.ApplyPropertyValue(TextElement.ForegroundProperty, Application.Current.Resources["EditorFg"]);
        sel.ApplyPropertyValue(TextElement.BackgroundProperty, null);
    }
    private void InsertLink_Click(object s, RoutedEventArgs e)
    {
        var win = new PromptWindow("Insert hyperlink", "URL:", "https://");
        if (win.ShowDialog() == true && Uri.TryCreate(win.Value, UriKind.Absolute, out var uri))
        {
            if (Rtb.Selection.IsEmpty)
            {
                var run = new Run(uri.ToString());
                var hl = new Hyperlink(run) { NavigateUri = uri };
                hl.RequestNavigate += (_, ev) => { Process.Start(new ProcessStartInfo(ev.Uri.ToString()) { UseShellExecute = true }); ev.Handled = true; };
                Rtb.CaretPosition.Paragraph?.Inlines.Add(hl);
            }
            else
            {
                var hl = new Hyperlink(Rtb.Selection.Start, Rtb.Selection.End) { NavigateUri = uri };
                hl.RequestNavigate += (_, ev) => { Process.Start(new ProcessStartInfo(ev.Uri.ToString()) { UseShellExecute = true }); ev.Handled = true; };
            }
            PersistRichText();
        }
    }

    private static readonly Brush TableBorder = new SolidColorBrush(Color.FromRgb(0x9A, 0xA0, 0xA6));

    private void InsertTable_Click(object sender, RoutedEventArgs e)
    {
        var win = new PromptWindow("Insert table", "Size as rows x columns (e.g. 3x4):", "3x3") { Owner = Window.GetWindow(this) };
        if (win.ShowDialog() != true) return;
        var m = System.Text.RegularExpressions.Regex.Match(win.Value ?? "", @"^\s*(\d+)\s*[xX*]\s*(\d+)\s*$");
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
                {
                    BorderBrush = TableBorder,
                    BorderThickness = new Thickness(0.6),
                    Padding = new Thickness(3, 1, 3, 1)
                };
                if (r == 0) cell.FontWeight = FontWeights.Bold;   // header row
                tr.Cells.Add(cell);
            }
            rg.Rows.Add(tr);
        }
        table.RowGroups.Add(rg);

        // Insert after the caret's block when possible; otherwise append to the document.
        var caretBlock = Rtb.CaretPosition?.Paragraph as Block;
        if (caretBlock != null && ReferenceEquals(caretBlock.Parent, Rtb.Document))
            Rtb.Document.Blocks.InsertAfter(caretBlock, table);
        else
            Rtb.Document.Blocks.Add(table);

        // Put the caret in the first cell so the user can start typing immediately.
        var firstCell = table.RowGroups[0].Rows[0].Cells[0];
        Rtb.CaretPosition = firstCell.ContentStart;
        Rtb.Focus();
        PersistRichText();
    }

    // ---- File bank ----
    private void Files_DragOver(object sender, DragEventArgs e)
    {
        e.Effects = e.Data.GetDataPresent(DataFormats.FileDrop) ? DragDropEffects.Copy : DragDropEffects.None;
        e.Handled = true;
    }
    private void Files_Drop(object sender, DragEventArgs e)
    {
        if (_container == null) return;
        if (e.Data.GetDataPresent(DataFormats.FileDrop))
        {
            // Hold Shift while dropping to LINK the items in place (no copy) — otherwise import a copy.
            bool linkInPlace = (e.KeyStates & DragDropKeyStates.ShiftKey) != 0;
            foreach (var path in (string[])e.Data.GetData(DataFormats.FileDrop)!)
            {
                if (linkInPlace) AddPathInPlace(path);
                else AddPath(path);
            }
            _repo?.MarkDirty();
            RefreshFileLists();
        }
    }

    /// <summary>Add a reference to a file/folder at its original location (no copy). A folder
    /// becomes a single entry that opens in Explorer; a file opens in its default editor.</summary>
    private void AddPathInPlace(string path)
    {
        if (_container == null) return;
        if (Directory.Exists(path))
        {
            _container.Files.Add(new FileItem
            {
                Name = new DirectoryInfo(path).Name + "  (folder)",
                Path = path,
                Kind = FileKind.Other,
                LinkInPlace = true,
                Added = DateTime.Now
            });
        }
        else if (File.Exists(path))
        {
            _container.Files.Add(new FileItem
            {
                Name = Path.GetFileName(path),
                Path = path,
                Kind = DataStore.ClassifyFile(path),
                LinkInPlace = true,
                Added = DateTime.Now
            });
        }
    }

    private void LinkInPlace_Click(object s, RoutedEventArgs e)
    {
        if (_container == null) return;
        var dlg = new OpenFileDialog
        {
            Multiselect = true,
            Title = "Link file(s) in place (the originals are referenced, not copied)"
        };
        if (dlg.ShowDialog() == true)
        {
            foreach (var f in dlg.FileNames) AddPathInPlace(f);
            _repo?.MarkDirty();
            RefreshFileLists();
        }
    }

    private void OpenAll_Click(object s, RoutedEventArgs e)
    {
        var lv = CurrentLv(); if (lv == null) return;
        var files = lv.Items.OfType<FileItem>().ToList();
        if (files.Count == 0) return;
        if (files.Count > 15 &&
            MessageBox.Show($"Open all {files.Count} items in this tab now?", "Open all",
                MessageBoxButton.YesNo, MessageBoxImage.Question) != MessageBoxResult.Yes) return;
        foreach (var fi in files) OpenFileItem(fi);
    }
    private void AddPath(string path)
    {
        if (_container == null) return;
        if (Directory.Exists(path))
        {
            foreach (var f in Directory.EnumerateFiles(path, "*", SearchOption.AllDirectories)) AddFilePath(f);
        }
        else if (File.Exists(path)) AddFilePath(path);
    }
    private void AddFilePath(string path)
    {
        if (_container == null) return;
        string stored;
        try { stored = DataStore.ImportFile(path); }
        catch { stored = path; }
        _container.Files.Add(new FileItem
        {
            Name = Path.GetFileName(path),
            Path = stored,
            Kind = DataStore.ClassifyFile(path),
            Added = DateTime.Now
        });
    }
    private void AddFile_Click(object s, RoutedEventArgs e)
    {
        var dlg = new OpenFileDialog { Multiselect = true };
        if (dlg.ShowDialog() == true)
        {
            foreach (var f in dlg.FileNames) AddFilePath(f);
            _repo?.MarkDirty();
            RefreshFileLists();
        }
    }
    private void AddFolder_Click(object s, RoutedEventArgs e)
    {
        var dlg = new System.Windows.Forms.FolderBrowserDialog();
        if (dlg.ShowDialog() == System.Windows.Forms.DialogResult.OK)
        {
            AddPath(dlg.SelectedPath);
            _repo?.MarkDirty();
            RefreshFileLists();
        }
    }
    private void AddLink_Click(object s, RoutedEventArgs e)
    {
        if (_container == null) return;
        var win = new PromptWindow("Add link", "URL:", "https://");
        if (win.ShowDialog() == true && !string.IsNullOrWhiteSpace(win.Value))
        {
            _container.Files.Add(new FileItem
            {
                Name = win.Value,
                Path = win.Value,
                Kind = FileKind.Link,
                IsLink = true
            });
            _repo?.MarkDirty();
            RefreshFileLists();
        }
    }
    private ListView? CurrentLv()
    {
        var t = FileTabs.SelectedItem as TabItem;
        return t?.Content as ListView;
    }
    private void Cut_Click(object s, RoutedEventArgs e)
    {
        var lv = CurrentLv(); if (lv == null) return;
        _clipboard = lv.SelectedItems.Cast<FileItem>().ToList(); _cutMode = true;
    }
    private void Copy_Click(object s, RoutedEventArgs e)
    {
        var lv = CurrentLv(); if (lv == null) return;
        _clipboard = lv.SelectedItems.Cast<FileItem>().ToList(); _cutMode = false;
    }
    private void Paste_Click(object s, RoutedEventArgs e)
    {
        if (_container == null || _clipboard.Count == 0) return;
        foreach (var f in _clipboard)
        {
            if (_cutMode)
            {
                if (!_container.Files.Contains(f)) _container.Files.Add(f);
            }
            else
            {
                _container.Files.Add(new FileItem
                {
                    Name = f.Name,
                    Path = f.Path,
                    Kind = f.Kind,
                    IsLink = f.IsLink,
                    LinkInPlace = f.LinkInPlace,
                    Added = DateTime.Now
                });
            }
        }
        _cutMode = false;
        _repo?.MarkDirty();
        RefreshFileLists();
    }
    private void RemoveFile_Click(object s, RoutedEventArgs e)
    {
        if (_container == null) return;
        var lv = CurrentLv(); if (lv == null) return;
        foreach (var f in lv.SelectedItems.Cast<FileItem>().ToList())
            _container.Files.Remove(f);
        _repo?.MarkDirty();
        RefreshFileLists();
    }
    private void OpenFile_Click(object s, RoutedEventArgs e) => OpenSelected();
    private void LvAll_DoubleClick(object s, MouseButtonEventArgs e) => OpenSelected();
    private void OpenSelected()
    {
        var lv = CurrentLv(); if (lv == null) return;
        if (lv.SelectedItem is FileItem fi) OpenFileItem(fi);
    }

    /// <summary>Open a file/folder/link with the OS default handler. In-place links and copies
    /// both open their real target, so editing the file saves straight back to its source.</summary>
    private void OpenFileItem(FileItem fi)
    {
        try
        {
            var target = fi.IsLink ? fi.Path : DataStore.ResolveFilePath(fi.Path);
            if (!fi.IsLink && !File.Exists(target) && !Directory.Exists(target))
            {
                MessageBox.Show($"Not found:\n{target}", "Open failed");
                return;
            }
            Process.Start(new ProcessStartInfo(target) { UseShellExecute = true });
        }
        catch (Exception ex) { MessageBox.Show(ex.Message, "Open failed"); }
    }

    // ---- Selection lock / unlock (protect highlighted text from editing) ----

    // Sentinel background colour used as the "this run is locked" marker. Round-trips through
    // DataFormats.Xaml save/load so the lock is durable without any side-channel storage.
    private static readonly Color LockedColor = Color.FromArgb(255, 255, 230, 153); // pale gold

    private static bool IsLockedRun(DependencyObject? d)
    {
        // The lock background may sit on the immediate Run OR on any wrapping Span
        // (WPF often sets background on an enclosing Span when the selection covers
        // multiple inline runs with mixed formatting). Walk the parent chain so we
        // detect the locked range either way.
        while (d is TextElement te)
        {
            if (te.Background is SolidColorBrush b && b.Color == LockedColor) return true;
            d = te.Parent;
        }
        return false;
    }

    /// <summary>True if any locked run lies inside (start, end). Endpoints touching a locked
    /// boundary do not count — that's a normal insertion point.</summary>
    private bool RangeOverlapsLocked(TextPointer start, TextPointer end)
    {
        if (start == null || end == null) return false;
        if (start.CompareTo(end) > 0) (start, end) = (end, start);
        var p = start;
        while (p != null && p.CompareTo(end) < 0)
        {
            if (IsLockedRun(p.Parent)) return true;
            var next = p.GetNextContextPosition(LogicalDirection.Forward);
            if (next == null) break;
            p = next;
        }
        return false;
    }

    /// <summary>True if the document currently holds any locked run. Walks the document once
    /// (cheap relative to the load that precedes it) checking each element's background against the
    /// lock sentinel — accurate where a serialized-XAML substring test was not.</summary>
    private bool DocumentContainsLock()
    {
        var p = Rtb.Document.ContentStart;
        var end = Rtb.Document.ContentEnd;
        while (p != null && p.CompareTo(end) < 0)
        {
            if (IsLockedRun(p.Parent)) return true;
            p = p.GetNextContextPosition(LogicalDirection.Forward);
        }
        return false;
    }

    private bool CaretInsideLocked(TextPointer caret)
    {
        if (caret == null) return false;
        // Caret is "inside" a locked run only when both immediate neighbours are inside it.
        var prev = caret.GetPositionAtOffset(-1, LogicalDirection.Backward);
        var next = caret.GetPositionAtOffset(1, LogicalDirection.Forward);
        return prev != null && next != null
            && IsLockedRun(prev.Parent) && IsLockedRun(next.Parent);
    }

    private void Rtb_PreviewKeyDown(object sender, KeyEventArgs e)
    {
        if (!_hasAnyLock) return;   // fast path: no locked text -> no per-key work
        // Locked text is ALWAYS uneditable. The app password only gates adding/removing the
        // lock itself (via the 🔒 / 🔓 toolbar buttons), not normal typing.
        var sel = Rtb.Selection;
        // Backspace: would delete the char to the left of the caret.
        if (e.Key == Key.Back && sel.IsEmpty)
        {
            var prev = Rtb.CaretPosition.GetNextInsertionPosition(LogicalDirection.Backward);
            if (prev != null && RangeOverlapsLocked(prev, Rtb.CaretPosition)) { e.Handled = true; ShowLockedHint(); }
            return;
        }
        if (e.Key == Key.Delete && sel.IsEmpty)
        {
            var next = Rtb.CaretPosition.GetNextInsertionPosition(LogicalDirection.Forward);
            if (next != null && RangeOverlapsLocked(Rtb.CaretPosition, next)) { e.Handled = true; ShowLockedHint(); }
            return;
        }
        // Any other key that would modify text while a locked range is selected.
        if (!sel.IsEmpty && RangeOverlapsLocked(sel.Start, sel.End) && IsModifyingKey(e))
        {
            e.Handled = true; ShowLockedHint();
        }
    }

    private static bool IsModifyingKey(KeyEventArgs e)
    {
        if (e.Key is Key.Left or Key.Right or Key.Up or Key.Down or Key.Home or Key.End
            or Key.PageUp or Key.PageDown or Key.Tab or Key.LeftShift or Key.RightShift
            or Key.LeftCtrl or Key.RightCtrl or Key.LeftAlt or Key.RightAlt or Key.CapsLock
            or Key.Escape) return false;
        // Ctrl+C / Ctrl+A / Ctrl+F do not modify text.
        if ((Keyboard.Modifiers & ModifierKeys.Control) != 0 &&
            e.Key is Key.C or Key.A or Key.F or Key.Insert) return false;
        return true;
    }

    private void Rtb_PreviewTextInput(object sender, TextCompositionEventArgs e)
    {
        if (!_hasAnyLock) return;   // fast path
        var sel = Rtb.Selection;
        if (sel.IsEmpty)
        {
            if (CaretInsideLocked(Rtb.CaretPosition)) { e.Handled = true; ShowLockedHint(); }
        }
        else if (RangeOverlapsLocked(sel.Start, sel.End))
        {
            e.Handled = true; ShowLockedHint();
        }
    }

    private void Rtb_PreviewExecuted(object sender, System.Windows.Input.ExecutedRoutedEventArgs e)
    {
        if (!_hasAnyLock) return;   // fast path
        var cmd = e.Command;
        if (cmd == ApplicationCommands.Paste || cmd == ApplicationCommands.Cut
            || cmd == EditingCommands.Delete || cmd == EditingCommands.Backspace
            || cmd == EditingCommands.DeleteNextWord || cmd == EditingCommands.DeletePreviousWord)
        {
            var sel = Rtb.Selection;
            bool blocked = sel.IsEmpty
                ? CaretInsideLocked(Rtb.CaretPosition)
                : RangeOverlapsLocked(sel.Start, sel.End);
            if (blocked) { e.Handled = true; ShowLockedHint(); }
        }
    }

    private DateTime _lastHint;
    private void ShowLockedHint()
    {
        // Throttle so each blocked key doesn't spam a dialog.
        if ((DateTime.Now - _lastHint).TotalMilliseconds < 1500) return;
        _lastHint = DateTime.Now;
        var win = Window.GetWindow(this);
        var status = win?.FindName("StatusBlock") as TextBlock;
        if (status != null) status.Text = "🔒 Highlighted/touched text is locked. Select it and click 🔓 to unlock.";
        else SystemSounds.Beep.Play();
    }

    private void Lock_Click(object sender, RoutedEventArgs e)
    {
        if (_container == null) return;
        var sel = Rtb.Selection;
        if (sel.IsEmpty)
        {
            MessageBox.Show("Highlight the text you want to protect from editing, then click 🔒.",
                "Lock highlighted text", MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }
        if (!EnsureUnlocked()) return;

        // Apply the sentinel background to the entire selection. WPF will split runs as needed.
        Rtb.Selection.ApplyPropertyValue(TextElement.BackgroundProperty, new SolidColorBrush(LockedColor));
        _hasAnyLock = true;
        FlushPending();
    }

    private void Unlock_Click(object sender, RoutedEventArgs e)
    {
        if (_container == null) return;
        var sel = Rtb.Selection;
        if (sel.IsEmpty)
        {
            MessageBox.Show("Highlight the locked text you want to unlock, then click 🔓.",
                "Unlock highlighted text", MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }
        if (!EnsureUnlocked()) return;

        // Walk the selection and, for any position inside a locked range, find the actual
        // TextElement that carries the sentinel background (it may be a wrapping Span, not
        // the immediate Run) and clear ONLY that background. Other backgrounds are preserved.
        var visited = new HashSet<TextElement>();
        var p = sel.Start;
        var end = sel.End;
        while (p != null && p.CompareTo(end) < 0)
        {
            var owner = LockedAncestor(p.Parent);
            if (owner != null && visited.Add(owner))
                owner.ClearValue(TextElement.BackgroundProperty);
            var nxt = p.GetNextContextPosition(LogicalDirection.Forward);
            if (nxt == null) break;
            p = nxt;
        }
        FlushPending();
        // Any locked runs left? (Keeps the per-keystroke fast path accurate.)
        _hasAnyLock = DocumentContainsLock();
    }

    private static TextElement? LockedAncestor(DependencyObject? d)
    {
        while (d is TextElement te)
        {
            if (te.Background is SolidColorBrush b && b.Color == LockedColor) return te;
            d = te.Parent;
        }
        return null;
    }

    /// <summary>Prompt for the app password (or to create one) and unlock the in-memory session.
    /// Returns true if the session is unlocked after the call.</summary>
    private bool EnsureUnlocked()
    {
        if (PasswordService.IsUnlocked) return true;
        if (!PasswordService.HasPassword)
        {
            var setup = new PasswordWindow(PasswordWindow.Mode.SetNew) { Owner = Window.GetWindow(this) };
            if (setup.ShowDialog() != true) return false;
            var (h, s) = PasswordService.SetPassword(setup.Password);
            DataStore.SavePasswordSettings(h, s);
            return true;
        }
        var dlg = new PasswordWindow(PasswordWindow.Mode.Unlock) { Owner = Window.GetWindow(this) };
        if (dlg.ShowDialog() != true) return false;
        return PasswordService.Unlock(dlg.Password);
    }
}
