using System;
using System.Collections.Generic;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;

namespace AA.Views;

/// <summary>Lets the user pick a custom background colour for each main tab (or reset to the theme
/// default). Returns the chosen colours as a hex map keyed by tab name in <see cref="Result"/>.</summary>
public partial class TabColorsWindow : Window
{
    private readonly List<(string Key, string Label)> _tabs;
    private readonly Dictionary<string, string> _working;
    private readonly Dictionary<string, Border> _swatches = new();

    /// <summary>Chosen colours, keyed by tab name (only tabs with a custom colour appear). Valid after OK.</summary>
    public Dictionary<string, string> Result { get; private set; } = new();

    public TabColorsWindow(List<(string Key, string Label)> tabs, Dictionary<string, string> current)
    {
        InitializeComponent();
        _tabs = tabs;
        _working = new Dictionary<string, string>(current);
        BuildRows();
    }

    private void BuildRows()
    {
        foreach (var (key, label) in _tabs)
        {
            var row = new DockPanel { Margin = new Thickness(0, 3, 0, 3) };
            row.Children.Add(new TextBlock { Text = label, Width = 190, VerticalAlignment = VerticalAlignment.Center, TextTrimming = TextTrimming.CharacterEllipsis });

            var swatch = new Border
            {
                Width = 46, Height = 24, CornerRadius = new CornerRadius(4),
                BorderBrush = (Brush)FindResource("BorderB"), BorderThickness = new Thickness(1),
                Margin = new Thickness(0, 0, 8, 0), VerticalAlignment = VerticalAlignment.Center
            };
            _swatches[key] = swatch;
            UpdateSwatch(key);

            var pick = new Button { Content = "Pick...", Padding = new Thickness(10, 3, 10, 3), Margin = new Thickness(0, 0, 6, 0) };
            pick.Click += (_, _) => PickColor(key);
            var reset = new Button { Content = "Default", Padding = new Thickness(10, 3, 10, 3) };
            reset.Click += (_, _) => { _working.Remove(key); UpdateSwatch(key); };

            DockPanel.SetDock(pick, Dock.Right);
            DockPanel.SetDock(reset, Dock.Right);
            row.Children.Add(reset);
            row.Children.Add(pick);
            row.Children.Add(swatch);
            FormHost.Children.Add(row);
        }
    }

    private void UpdateSwatch(string key)
    {
        var swatch = _swatches[key];
        if (_working.TryGetValue(key, out var hex) && TryColor(hex, out var c))
        {
            swatch.Background = new SolidColorBrush(c);
            swatch.Child = null;
        }
        else
        {
            swatch.Background = (Brush)FindResource("Panel");
            swatch.Child = new TextBlock
            {
                Text = "default", FontSize = 10, Foreground = (Brush)FindResource("Muted"),
                HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center
            };
        }
    }

    private void PickColor(string key)
    {
        using var dlg = new System.Windows.Forms.ColorDialog { FullOpen = true };
        if (_working.TryGetValue(key, out var hex) && TryColor(hex, out var cur))
            dlg.Color = System.Drawing.Color.FromArgb(cur.A, cur.R, cur.G, cur.B);
        if (dlg.ShowDialog() != System.Windows.Forms.DialogResult.OK) return;
        var col = dlg.Color;
        _working[key] = $"#{col.R:X2}{col.G:X2}{col.B:X2}";
        UpdateSwatch(key);
    }

    private void ResetAll_Click(object sender, RoutedEventArgs e)
    {
        _working.Clear();
        foreach (var (key, _) in _tabs) UpdateSwatch(key);
    }

    private void Apply_Click(object sender, RoutedEventArgs e)
    {
        Result = new Dictionary<string, string>(_working);
        DialogResult = true;
        Close();
    }

    private void Cancel_Click(object sender, RoutedEventArgs e) { DialogResult = false; Close(); }

    private static bool TryColor(string hex, out Color color)
    {
        try { color = (Color)ColorConverter.ConvertFromString(hex); return true; }
        catch { color = Colors.Transparent; return false; }
    }
}
