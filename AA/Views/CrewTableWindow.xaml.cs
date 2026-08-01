using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Data;
using AA.Models;
using AA.Services;
using Microsoft.Win32;

namespace AA.Views;

/// <summary>A tabulated, all-crew view in its own window. The user picks which columns to show and their
/// order (from the full <see cref="CrewColumns"/> catalog), sets the date format + separator, and can
/// export the exact table to a .xlsx workbook. Column/format choices persist in <see cref="UiState"/>.</summary>
public partial class CrewTableWindow : Window
{
    private readonly AppRepository _repo;
    private readonly IReadOnlyList<CrewMember> _crew;
    private readonly ObservableCollection<ColumnChoice> _choices = new();
    private bool _loading;

    private sealed record FmtOption(CrewDateFormat Value, string Label);

    public CrewTableWindow(AppRepository repo, IReadOnlyList<CrewMember> crew)
    {
        InitializeComponent();
        _repo = repo;
        _crew = crew;

        _loading = true;

        FormatBox.ItemsSource = new[]
        {
            new FmtOption(CrewDateFormat.Iso,          "2026-03-15  (Y-M-D)"),
            new FmtOption(CrewDateFormat.DayMonthYear, "15-03-2026  (D-M-Y)"),
            new FmtOption(CrewDateFormat.MonthDayYear, "03-15-2026  (M-D-Y)"),
            new FmtOption(CrewDateFormat.DayMonthName, "15-Mar-2026  (D-Mon-Y)"),
        };
        FormatBox.DisplayMemberPath = nameof(FmtOption.Label);
        FormatBox.SelectedItem = ((FmtOption[])FormatBox.ItemsSource)
            .FirstOrDefault(o => o.Value == LoadFormat()) ?? ((FmtOption[])FormatBox.ItemsSource)[0];

        SepBox.Text = string.IsNullOrEmpty(_repo.Data.Ui.CrewTableDateSeparator) ? "-" : _repo.Data.Ui.CrewTableDateSeparator!;

        BuildChoices();
        ColsBox.ItemsSource = _choices;

        _loading = false;
        Rebuild();

        Closed += (_, _) => Persist();   // final save of any last tweak
    }

    private sealed class ColumnChoice : INotifyPropertyChanged
    {
        public required string Key { get; init; }
        public required string Header { get; init; }
        private bool _shown;
        public bool Shown { get => _shown; set { if (_shown != value) { _shown = value; PropertyChanged?.Invoke(this, new(nameof(Shown))); } } }
        public event PropertyChangedEventHandler? PropertyChanged;
    }

    private CrewDateFormat LoadFormat() =>
        Enum.TryParse<CrewDateFormat>(_repo.Data.Ui.CrewTableDateFormat, out var f) ? f : CrewDateFormat.Iso;

    private CrewDateFormat CurrentFormat() => (FormatBox.SelectedItem as FmtOption)?.Value ?? CrewDateFormat.Iso;
    private string CurrentSeparator() => SepBox.Text ?? "-";

    /// <summary>Populate the chooser: saved (shown) columns first in their saved order, then every remaining
    /// column unchecked, so the user can add any of the full catalog.</summary>
    private void BuildChoices()
    {
        _choices.Clear();
        var byKey = CrewColumns.All.ToDictionary(c => c.Key, StringComparer.Ordinal);
        var used = new HashSet<string>(StringComparer.Ordinal);
        var order = _repo.Data.Ui.CrewTableColumns;

        if (order == null || order.Count == 0)
        {
            // Never configured: show the defaults (in default order), everything else available but hidden.
            foreach (var key in CrewColumns.Defaults)
                if (byKey.TryGetValue(key, out var col) && used.Add(col.Key))
                    _choices.Add(NewChoice(col, true));
            foreach (var col in CrewColumns.All)
                if (used.Add(col.Key)) _choices.Add(NewChoice(col, false));
            return;
        }

        // Configured: honour the full saved order AND which were shown (so hidden columns keep their place
        // and an all-unticked selection is respected instead of reverting to defaults).
        var shown = new HashSet<string>(_repo.Data.Ui.CrewTableShownColumns ?? new List<string>(), StringComparer.Ordinal);
        foreach (var key in order)
            if (byKey.TryGetValue(key, out var col) && used.Add(col.Key))
                _choices.Add(NewChoice(col, shown.Contains(col.Key)));
        // Columns added to the catalog since the config was saved appear at the end, hidden.
        foreach (var col in CrewColumns.All)
            if (used.Add(col.Key)) _choices.Add(NewChoice(col, false));
    }

    private static ColumnChoice NewChoice(CrewColumn col, bool shown)
        => new() { Key = col.Key, Header = col.Header, Shown = shown };

    private List<CrewColumn> ShownColumns()
    {
        var byKey = CrewColumns.All.ToDictionary(c => c.Key, StringComparer.Ordinal);
        return _choices.Where(c => c.Shown).Select(c => byKey[c.Key]).ToList();
    }

    private void Rebuild()
    {
        if (_loading) return;
        var cols = ShownColumns();
        var fmt = CurrentFormat();
        var sep = CurrentSeparator();

        Grid.Columns.Clear();
        foreach (var col in cols)
            Grid.Columns.Add(new GridViewColumn
            {
                Header = col.Header,
                DisplayMemberBinding = new Binding($"[{col.Key}]") { Mode = BindingMode.OneWay }
            });

        var rows = new List<Dictionary<string, string>>(_crew.Count);
        foreach (var m in _crew)
        {
            var row = new Dictionary<string, string>(cols.Count, StringComparer.Ordinal);
            foreach (var col in cols) row[col.Key] = CrewColumns.Cell(col, m, fmt, sep);
            rows.Add(row);
        }
        Table.ItemsSource = rows;

        CountText.Text = $"{_crew.Count} crew  ·  {cols.Count} column{(cols.Count == 1 ? "" : "s")}";
        Persist();
    }

    private void Persist()
    {
        _repo.Data.Ui.CrewTableColumns = _choices.Select(c => c.Key).ToList();               // full order (all)
        _repo.Data.Ui.CrewTableShownColumns = _choices.Where(c => c.Shown).Select(c => c.Key).ToList();
        _repo.Data.Ui.CrewTableDateFormat = CurrentFormat().ToString();
        _repo.Data.Ui.CrewTableDateSeparator = CurrentSeparator();
        _repo.MarkDirty();
    }

    // ---- events ----
    private void Config_Changed(object sender, SelectionChangedEventArgs e) => Rebuild();
    private void Sep_Changed(object sender, TextChangedEventArgs e) => Rebuild();
    private void Shown_Changed(object sender, RoutedEventArgs e) => Rebuild();

    private void Up_Click(object sender, RoutedEventArgs e) => Move(-1);
    private void Down_Click(object sender, RoutedEventArgs e) => Move(1);

    private void Move(int dir)
    {
        int i = ColsBox.SelectedIndex;
        if (i < 0) return;
        int j = i + dir;
        if (j < 0 || j >= _choices.Count) return;
        _choices.Move(i, j);
        ColsBox.SelectedIndex = j;
        Rebuild();
    }

    private void All_Click(object sender, RoutedEventArgs e) => SetAll(true);
    private void None_Click(object sender, RoutedEventArgs e) => SetAll(false);
    private void SetAll(bool shown)
    {
        _loading = true;
        foreach (var c in _choices) c.Shown = shown;
        _loading = false;
        Rebuild();
    }

    private void Export_Click(object sender, RoutedEventArgs e)
    {
        var cols = ShownColumns();
        if (cols.Count == 0)
        {
            MessageBox.Show(this, "Tick at least one column to export.", "Export to Excel",
                MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }
        var dlg = new SaveFileDialog
        {
            Title = "Export crew table to Excel",
            Filter = "Excel workbook (*.xlsx)|*.xlsx",
            DefaultExt = ".xlsx",
            FileName = $"crew-{DateTime.Now:yyyy-MM-dd}.xlsx"
        };
        if (dlg.ShowDialog(this) != true) return;

        var fmt = CurrentFormat();
        var sep = CurrentSeparator();
        var headers = cols.Select(c => c.Header).ToList();
        var rows = _crew.Select(m => cols.Select(c => CrewColumns.Cell(c, m, fmt, sep)).ToArray()).ToList();
        try
        {
            XlsxWriter.Write(dlg.FileName, "Crew", headers, rows);
            if (MessageBox.Show(this, $"Exported {rows.Count} crew to:\n{dlg.FileName}\n\nOpen it now?",
                    "Export complete", MessageBoxButton.YesNo, MessageBoxImage.Information) == MessageBoxResult.Yes)
                System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(dlg.FileName) { UseShellExecute = true });
        }
        catch (Exception ex)
        {
            MessageBox.Show(this, $"Could not export the workbook:\n\n{ex.Message}", "Export failed",
                MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }

    private void Close_Click(object sender, RoutedEventArgs e) => Close();
}
