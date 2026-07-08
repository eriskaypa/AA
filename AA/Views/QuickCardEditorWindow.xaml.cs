using System;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using AA.Models;
using AA.Services;
using Microsoft.Win32;

namespace AA.Views;

public partial class QuickCardEditorWindow : Window
{
    private readonly QuickCard _card;
    private bool _suppress;

    public QuickCardEditorWindow(QuickCard card)
    {
        InitializeComponent();
        _card = card;

        _suppress = true;
        TitleBox.Text = card.Title;
        WidthBox.Text = ((int)card.Width).ToString();
        HeightBox.Text = ((int)card.Height).ToString();
        BuildIconPicker();
        BuildColorSwatches();
        UpdateTargetUi();
        _suppress = false;

        UpdatePreview();
        Loaded += (_, _) => TitleBox.Focus();
    }

    private void BuildIconPicker()
    {
        foreach (var (glyph, name) in MaritimeIcons.All)
        {
            var btn = new Button
            {
                Content = glyph,
                FontSize = 20,
                Width = 40,
                Height = 36,
                Margin = new Thickness(2),
                ToolTip = name,
                Tag = glyph
            };
            btn.Click += (_, _) => { _card.Icon = glyph; UpdatePreview(); };
            IconPanel.Children.Add(btn);
        }
    }

    private void BuildColorSwatches()
    {
        foreach (var hex in MaritimeIcons.Palette)
        {
            var sw = new Button
            {
                Width = 28,
                Height = 28,
                Margin = new Thickness(2),
                Background = MaritimeIcons.BackgroundBrush(hex),
                BorderBrush = (Brush)FindResource("BorderB"),
                BorderThickness = new Thickness(1),
                Tag = hex,
                ToolTip = hex
            };
            sw.Click += (_, _) => { _card.Color = hex; UpdatePreview(); };
            ColorPanel.Children.Add(sw);
        }
    }

    private void Title_Changed(object sender, TextChangedEventArgs e)
    {
        if (_suppress) return;
        _card.Title = TitleBox.Text;
        UpdatePreview();
    }

    private void Size_Changed(object sender, TextChangedEventArgs e)
    {
        if (_suppress) return;
        if (double.TryParse(WidthBox.Text, out var w) && w >= 80) _card.Width = Math.Min(900, w);
        if (double.TryParse(HeightBox.Text, out var h) && h >= 60) _card.Height = Math.Min(700, h);
    }

    private void LinkFile_Click(object sender, RoutedEventArgs e)
    {
        var dlg = new OpenFileDialog { Title = "Link a file in place (no copy)" };
        if (dlg.ShowDialog() != true) return;
        _card.Target = dlg.FileName;
        _card.IsLink = false; _card.LinkInPlace = true; _card.IsFolder = false;
        if (string.IsNullOrWhiteSpace(_card.Title)) SetTitle(System.IO.Path.GetFileNameWithoutExtension(dlg.FileName));
        UpdateTargetUi(); UpdatePreview();
    }

    private void ImportCopy_Click(object sender, RoutedEventArgs e)
    {
        var dlg = new OpenFileDialog { Title = "Import a copy of a file" };
        if (dlg.ShowDialog() != true) return;
        try { _card.Target = DataStore.ImportFile(dlg.FileName); }
        catch (Exception ex) { MessageBox.Show(this, ex.Message, "Import failed", MessageBoxButton.OK, MessageBoxImage.Error); return; }
        _card.IsLink = false; _card.LinkInPlace = false; _card.IsFolder = false;
        if (string.IsNullOrWhiteSpace(_card.Title)) SetTitle(System.IO.Path.GetFileNameWithoutExtension(dlg.FileName));
        UpdateTargetUi(); UpdatePreview();
    }

    private void LinkFolder_Click(object sender, RoutedEventArgs e)
    {
        var dlg = new System.Windows.Forms.FolderBrowserDialog { Description = "Link a folder (opens in Explorer)" };
        if (dlg.ShowDialog() != System.Windows.Forms.DialogResult.OK) return;
        _card.Target = dlg.SelectedPath;
        _card.IsLink = false; _card.LinkInPlace = true; _card.IsFolder = true;
        if (string.IsNullOrWhiteSpace(_card.Title)) SetTitle(new System.IO.DirectoryInfo(dlg.SelectedPath).Name);
        UpdateTargetUi(); UpdatePreview();
    }

    private void WebLink_Click(object sender, RoutedEventArgs e)
    {
        var p = new PromptWindow("Web link", "URL:", "https://") { Owner = this };
        if (p.ShowDialog() != true || string.IsNullOrWhiteSpace(p.Value)) return;
        _card.Target = p.Value.Trim();
        _card.IsLink = true; _card.LinkInPlace = false; _card.IsFolder = false;
        UpdateTargetUi(); UpdatePreview();
    }

    private void CustomColor_Click(object sender, RoutedEventArgs e)
    {
        var c = MaritimeIcons.ParseColor(_card.Color);
        var dlg = new System.Windows.Forms.ColorDialog { Color = System.Drawing.Color.FromArgb(c.A, c.R, c.G, c.B), FullOpen = true };
        if (dlg.ShowDialog() == System.Windows.Forms.DialogResult.OK)
        {
            _card.Color = $"#FF{dlg.Color.R:X2}{dlg.Color.G:X2}{dlg.Color.B:X2}";
            UpdatePreview();
        }
    }

    private void SetTitle(string t)
    {
        _suppress = true; TitleBox.Text = t; _suppress = false;
        _card.Title = t;
    }

    private void UpdateTargetUi()
    {
        TargetBox.Text = string.IsNullOrWhiteSpace(_card.Target) ? "(none — pick a file, folder, or web link)" : _card.Target;
        TypeLabel.Text =
            string.IsNullOrWhiteSpace(_card.Target) ? "" :
            _card.IsLink ? "Web link" :
            _card.IsFolder ? "Folder (live)" :
            _card.LinkInPlace ? "File (live)" : "Imported copy";
    }

    private void UpdatePreview()
    {
        PreviewCard.Background = MaritimeIcons.BackgroundBrush(_card.Color);
        var fg = MaritimeIcons.ReadableForegroundBrush(_card.Color);
        PrevIcon.Text = _card.Icon;
        PrevIcon.Foreground = fg;
        PrevTitle.Text = string.IsNullOrWhiteSpace(_card.Title) ? "(untitled)" : _card.Title;
        PrevTitle.Foreground = fg;
    }

    private void Ok_Click(object sender, RoutedEventArgs e) { DialogResult = true; Close(); }
    private void Cancel_Click(object sender, RoutedEventArgs e) { DialogResult = false; Close(); }
}
