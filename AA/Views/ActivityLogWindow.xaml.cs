using System;
using System.IO;
using System.Linq;
using System.Text;
using System.Windows;
using System.Windows.Controls;
using AA.Models;
using AA.Services;
using Microsoft.Win32;

namespace AA.Views;

/// <summary>Shows the append-only activity log (entries added / removed, UTC-timestamped), newest first.</summary>
public partial class ActivityLogWindow : Window
{
    private readonly AppRepository _repo;

    public ActivityLogWindow(AppRepository repo)
    {
        InitializeComponent();
        _repo = repo;
        Refresh();
    }

    private void Refresh()
    {
        var q = SearchBox.Text?.Trim() ?? "";
        var all = _repo.Data.Log.Reverse().ToList();   // newest first
        var rows = string.IsNullOrEmpty(q)
            ? all
            : all.Where(e =>
                e.Action.Contains(q, StringComparison.OrdinalIgnoreCase) ||
                e.Kind.Contains(q, StringComparison.OrdinalIgnoreCase) ||
                e.Name.Contains(q, StringComparison.OrdinalIgnoreCase) ||
                e.Detail.Contains(q, StringComparison.OrdinalIgnoreCase)).ToList();
        List.ItemsSource = rows;
        CountText.Text = $"{rows.Count} of {_repo.Data.Log.Count} log entries.";
    }

    private void Search_Changed(object sender, TextChangedEventArgs e) => Refresh();

    private void Clear_Click(object sender, RoutedEventArgs e)
    {
        if (_repo.Data.Log.Count == 0) return;
        if (MessageBox.Show(this, $"Clear all {_repo.Data.Log.Count} activity-log entries? This can't be undone.",
                "Clear activity log", MessageBoxButton.YesNo, MessageBoxImage.Warning) != MessageBoxResult.Yes) return;
        _repo.Data.Log.Clear();
        _repo.Save();
        Refresh();
    }

    private void Export_Click(object sender, RoutedEventArgs e)
    {
        var dlg = new SaveFileDialog
        {
            Title = "Export activity log",
            Filter = "CSV file (*.csv)|*.csv|All files (*.*)|*.*",
            FileName = $"aa-activity-log-{DateTime.UtcNow:yyyyMMdd-HHmmss}.csv"
        };
        if (dlg.ShowDialog(this) != true) return;
        try
        {
            var sb = new StringBuilder();
            sb.AppendLine("TimestampUTC,LocalTime,Action,Kind,Name,Detail");
            foreach (var en in _repo.Data.Log)   // chronological order in the export
                sb.AppendLine(string.Join(",", Csv(en.TimeUtc), Csv(en.TimeLocal), Csv(en.Action), Csv(en.Kind), Csv(en.Name), Csv(en.Detail)));
            File.WriteAllText(dlg.FileName, sb.ToString());
            try { System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(dlg.FileName) { UseShellExecute = true }); } catch { }
        }
        catch (Exception ex)
        {
            MessageBox.Show(this, ex.Message, "Export failed", MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }

    private static string Csv(string s)
    {
        s ??= "";
        if (s.Contains(',') || s.Contains('"') || s.Contains('\n'))
            return "\"" + s.Replace("\"", "\"\"") + "\"";
        return s;
    }
}
