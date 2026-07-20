using System;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text;
using System.Windows;
using System.Windows.Documents;
using System.Windows.Navigation;
using AA.Models;
using AA.Services;

namespace AA.Views;

/// <summary>Read-only view of a <see cref="Container"/> — its rich-text body and file bank. Used to peek
/// inside a saved-list item without opening the editable builder (and without exporting a PDF just to
/// reach the links): hyperlinks are clickable and files open on double-click, but nothing can be edited,
/// so a reusable saved list can't be changed by accident.</summary>
public partial class ContainerViewerWindow : Window
{
    private readonly Container _container;

    public ContainerViewerWindow(string title, Container container, string? subtitle = null)
    {
        InitializeComponent();
        _container = container;
        Title = $"View — {title}";
        TitleText.Text = title;
        if (!string.IsNullOrWhiteSpace(subtitle)) SubText.Text = subtitle;

        LoadBody();

        FilesList.ItemsSource = container.Files;
        FilesHeader.Text = container.Files.Count == 0
            ? "Files — none"
            : $"Files ({container.Files.Count}) — double-click to open";

        // One handler catches every hyperlink in the loaded document (the per-link handlers the editor
        // wires up at creation time are not part of the saved XAML).
        Rtb.AddHandler(Hyperlink.RequestNavigateEvent, new RequestNavigateEventHandler(Link_Navigate));
    }

    private void LoadBody()
    {
        var xaml = _container.RichTextXaml;
        if (string.IsNullOrWhiteSpace(xaml) || PasswordService.IsEncrypted(xaml))
        {
            Rtb.Document.Blocks.Clear();
            Rtb.Document.Blocks.Add(new Paragraph(new Run(
                PasswordService.IsEncrypted(xaml) ? "(locked content)" : "(no notes)"))
            { Foreground = System.Windows.Media.Brushes.Gray });
            return;
        }
        try
        {
            using var ms = new MemoryStream(Encoding.UTF8.GetBytes(xaml));
            new TextRange(Rtb.Document.ContentStart, Rtb.Document.ContentEnd).Load(ms, DataFormats.Xaml);
        }
        catch
        {
            Rtb.Document.Blocks.Clear();
            Rtb.Document.Blocks.Add(new Paragraph(new Run(xaml)));
        }
    }

    private void Link_Navigate(object sender, RequestNavigateEventArgs e)
    {
        Open(e.Uri?.ToString());
        e.Handled = true;
    }

    private void Files_DoubleClick(object sender, System.Windows.Input.MouseButtonEventArgs e)
    {
        if (FilesList.SelectedItem is FileItem f) OpenFile(f);
    }

    private void OpenAll_Click(object sender, RoutedEventArgs e)
    {
        var files = _container.Files.ToList();
        if (files.Count == 0)
        {
            MessageBox.Show(this, "This item has no files.", "Open all files",
                MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }
        if (files.Count > 15 && MessageBox.Show(this, $"Open all {files.Count} files?", "Open all files",
                MessageBoxButton.YesNo, MessageBoxImage.Question) != MessageBoxResult.Yes) return;
        foreach (var f in files) OpenFile(f);
    }

    private void OpenFile(FileItem f)
    {
        var target = f.IsLink ? f.Path : DataStore.ResolveFilePath(f.Path);
        if (!f.IsLink && !File.Exists(target) && !Directory.Exists(target))
        {
            MessageBox.Show(this, $"That file is missing:\n\n{target}", "Open file",
                MessageBoxButton.OK, MessageBoxImage.Warning);
            return;
        }
        Open(target);
    }

    private void Open(string? target)
    {
        if (string.IsNullOrWhiteSpace(target)) return;
        try { Process.Start(new ProcessStartInfo(target) { UseShellExecute = true }); }
        catch (Exception ex)
        {
            MessageBox.Show(this, $"Could not open:\n\n{target}\n\n{ex.Message}", "Open",
                MessageBoxButton.OK, MessageBoxImage.Warning);
        }
    }

    private void Close_Click(object sender, RoutedEventArgs e) => Close();
}
