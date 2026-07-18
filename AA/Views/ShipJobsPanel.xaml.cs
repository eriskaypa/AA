using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Threading;
using AA.Models;
using AA.Services;
using Microsoft.Win32;

namespace AA.Views;

/// <summary>Per-ship Shippalm work-order (PMS) view: import a Work Order List, analyse it, filter it,
/// and choose which recurring jobs raise notifications.</summary>
public partial class ShipJobsPanel : UserControl
{
    private AppRepository? _repo;
    private Vessel? _vessel;

    private const int DueSoonDays = 90;   // "due soon" horizon for filtering / analysis

    private string _sortColumn = "Due";   // current sort column (header text)
    private bool _sortDescending;
    private bool _populating;             // guard so populating the filter combos doesn't rebuild repeatedly

    private static readonly Brush RedBrush    = Frozen("#FFD45050");
    private static readonly Brush OrangeBrush = Frozen("#FFE8890C");
    private static readonly Brush AmberBrush  = Frozen("#FFC9A227");
    private static readonly Brush GreenBrush  = Frozen("#FF2E9E5B");
    private static readonly Brush GrayBrush   = Frozen("#FF8A8A8A");
    private static SolidColorBrush Frozen(string hex)
    { var b = new SolidColorBrush((Color)ColorConverter.ConvertFromString(hex)); b.Freeze(); return b; }

    private readonly DispatcherTimer _searchDebounce;

    public ShipJobsPanel()
    {
        InitializeComponent();
        // Debounce the search box so typing doesn't re-filter/rebuild thousands of rows per keystroke.
        _searchDebounce = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(200) };
        _searchDebounce.Tick += (_, _) => { _searchDebounce.Stop(); BuildView(); };
    }

    public void Load(Vessel vessel, AppRepository repo)
    {
        _vessel = vessel;
        _repo = repo;
        NotifEnabledChk.IsChecked = vessel.NotificationsEnabled;
        PopulateFilters();
        BuildView();
    }

    private void PopulateFilters()
    {
        if (_vessel == null) return;
        _populating = true;
        FillCombo(StatusFilter, "(all statuses)", _vessel.Jobs.Select(j => j.Status));
        FillCombo(CategoryFilter, "(all categories)", _vessel.Jobs.Select(j => j.Category));
        FillCombo(RankFilter, "(all ranks)", _vessel.Jobs.Select(j => j.ResponsibleRank));
        if (CompletionFilter.Items.Count == 0)
        {
            CompletionFilter.ItemsSource = new List<string> { "All", "Active only", "Completed only" };
            CompletionFilter.SelectedIndex = 0;
        }
        _populating = false;
    }

    private static void FillCombo(ComboBox combo, string allLabel, IEnumerable<string> values)
    {
        var prev = combo.SelectedItem as string;
        var distinct = values.Where(s => !string.IsNullOrWhiteSpace(s))
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .OrderBy(s => s, StringComparer.OrdinalIgnoreCase).ToList();
        var items = new List<string> { allLabel };
        items.AddRange(distinct);
        combo.ItemsSource = items;
        combo.SelectedItem = prev != null && items.Contains(prev) ? prev : items[0];
    }

    // ---- Import ----
    private async void Import_Click(object sender, RoutedEventArgs e)
    {
        if (_repo == null || _vessel == null) return;
        var dlg = new OpenFileDialog
        {
            Title = $"Import Shippalm Work Order List for {_vessel.Name}",
            Filter = "Excel workbook (*.xlsx)|*.xlsx|All files (*.*)|*.*"
        };
        if (dlg.ShowDialog() != true) return;

        try
        {
            Mouse.OverrideCursor = Cursors.Wait;
            SummaryText.Text = "Reading Shippalm export… (large files take a few seconds)";
            var jobs = await Task.Run(() => ShippalmReader.Read(dlg.FileName));

            // Upsert by job number (the primary key). Preserve each existing job's Notify choice.
            var byNo = _vessel.Jobs
                .GroupBy(j => j.JobNo, StringComparer.OrdinalIgnoreCase)
                .ToDictionary(g => g.Key, g => g.First(), StringComparer.OrdinalIgnoreCase);
            int added = 0, updated = 0;
            foreach (var j in jobs)
            {
                if (byNo.TryGetValue(j.JobNo, out var existing))
                {
                    // Keep the user's per-job choices across re-import.
                    j.Notify = existing.Notify;
                    j.IsCompleted = existing.IsCompleted;
                    j.CompletedDate = existing.CompletedDate;
                    existing.CopyFrom(j);         // update in place — O(1), no O(n) IndexOf/replace
                    updated++;
                }
                else { _vessel.Jobs.Add(j); byNo[j.JobNo] = j; added++; }
            }
            _repo.Save();
            PopulateFilters();
            BuildView();
            StatusHint($"Imported {jobs.Count} work orders for {_vessel.Name} ({added} new, {updated} updated).");
        }
        catch (Exception ex)
        {
            MessageBox.Show(Window.GetWindow(this), $"Could not import the Shippalm file:\n\n{ex.Message}",
                "Import failed", MessageBoxButton.OK, MessageBoxImage.Error);
            BuildView();
        }
        finally { Mouse.OverrideCursor = null; }
    }

    // ---- Export (per vessel) ----
    private void Export_Click(object sender, RoutedEventArgs e)
    {
        if (_repo == null || _vessel == null) return;
        if (_vessel.Jobs.Count == 0)
        {
            MessageBox.Show(Window.GetWindow(this), "No work orders to export for this ship.",
                "Export", MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }
        var safe = string.Concat((_vessel.Name ?? "vessel")
            .Select(ch => System.IO.Path.GetInvalidFileNameChars().Contains(ch) ? '_' : ch));
        var dlg = new SaveFileDialog
        {
            Title = $"Export work orders for {_vessel.Name}",
            Filter = "Excel workbook (*.xlsx)|*.xlsx",
            FileName = $"WorkOrders-{safe}.xlsx",
            DefaultExt = ".xlsx",
            AddExtension = true
        };
        if (dlg.ShowDialog() != true) return;
        try
        {
            Mouse.OverrideCursor = Cursors.Wait;
            ShippalmReader.Write(_vessel.Jobs.ToList(), dlg.FileName);
        }
        catch (Exception ex)
        {
            MessageBox.Show(Window.GetWindow(this), $"Could not export:\n\n{ex.Message}",
                "Export failed", MessageBoxButton.OK, MessageBoxImage.Error);
            return;
        }
        finally { Mouse.OverrideCursor = null; }
        StatusHint($"Exported {_vessel.Jobs.Count} work orders for {_vessel.Name}.");
        try { System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(dlg.FileName) { UseShellExecute = true }); }
        catch { /* user can open it manually */ }
    }

    // ---- Per-ship notifications (kept inside this vessel's tab) ----
    private void NotifEnabled_Click(object sender, RoutedEventArgs e)
    {
        if (_repo == null || _vessel == null) return;
        _vessel.NotificationsEnabled = NotifEnabledChk.IsChecked == true;
        _repo.MarkDirty();
        _repo.FlushIfDirty();
        UpdateNotifications();
    }

    private void UpdateNotifications()
    {
        if (_vessel == null) return;
        NotifEnabledChk.IsChecked = _vessel.NotificationsEnabled;

        if (!_vessel.NotificationsEnabled)
        {
            NotifBar.BorderBrush = GrayBrush;
            NotifText.Foreground = GrayBrush;
            NotifText.Text = "Off — turn on to track this ship's due / overdue work orders here.";
            return;
        }

        var today = DateTime.Today;
        // Completed jobs are excluded from notifications (they're no longer outstanding).
        var flagged = _vessel.Jobs.Where(j => j.Notify && !j.IsCompleted).ToList();
        if (flagged.Count == 0)
        {
            NotifBar.BorderBrush = GrayBrush;
            NotifText.Foreground = (Brush)FindResource("Fg");
            NotifText.Text = "On — no active flagged jobs. Tick the Notify box (or “🔔 shown ON”) on the recurring jobs you want tracked.";
            return;
        }

        var overdue = flagged.Where(j => j.DaysUntilDue(today) is int d && d < 0)
            .OrderBy(j => j.DaysUntilDue(today)).ToList();
        var dueSoon = flagged.Where(j => j.DaysUntilDue(today) is int d && d >= 0 && d <= 30)
            .OrderBy(j => j.DaysUntilDue(today)).ToList();
        var attention = overdue.Concat(dueSoon).ToList();

        if (attention.Count == 0)
        {
            NotifBar.BorderBrush = GreenBrush;
            NotifText.Foreground = GreenBrush;
            NotifText.Text = $"On — {flagged.Count} flagged job(s), all clear (none due within 30 days).";
            return;
        }

        NotifBar.BorderBrush = overdue.Count > 0 ? RedBrush : OrangeBrush;
        NotifText.Foreground = overdue.Count > 0 ? RedBrush : OrangeBrush;
        var top = attention.Take(4).Select(j =>
        {
            int d = j.DaysUntilDue(today)!.Value;
            return d < 0 ? $"{j.JobNo} (overdue {-d}d)" : $"{j.JobNo} (in {d}d)";
        });
        NotifText.Text = $"⚠ {attention.Count} flagged work order(s) need attention — {overdue.Count} overdue, {dueSoon.Count} due ≤30d:  "
            + string.Join(",   ", top) + (attention.Count > 4 ? "   …" : "");
    }

    // ---- Filtering + view ----
    private void Filter_Changed(object sender, RoutedEventArgs e) { if (!_populating) BuildView(); }
    private void Filter_Changed(object sender, SelectionChangedEventArgs e) { if (!_populating) BuildView(); }
    private void Search_Changed(object sender, TextChangedEventArgs e)
    {
        _searchDebounce.Stop();
        _searchDebounce.Start();
    }

    private void Header_Click(object sender, RoutedEventArgs e)
    {
        // Fires for any header click; only act on a real, non-padding column header.
        if (e.OriginalSource is not GridViewColumnHeader h || h.Column?.Header is not string col || col.Length == 0) return;
        if (_sortColumn == col) _sortDescending = !_sortDescending;
        else { _sortColumn = col; _sortDescending = false; }
        BuildView();
    }

    private IEnumerable<ShipJob> Filtered()
    {
        if (_vessel == null) return Enumerable.Empty<ShipJob>();
        var today = DateTime.Today;
        IEnumerable<ShipJob> jobs = _vessel.Jobs;
        var oic = StringComparison.OrdinalIgnoreCase;

        var q = SearchBox.Text?.Trim() ?? "";
        if (!string.IsNullOrEmpty(q))
            jobs = jobs.Where(j =>
                j.JobNo.Contains(q, oic) ||
                j.Title.Contains(q, oic) ||
                j.FunctionDescription.Contains(q, oic) ||
                j.ResponsibleRank.Contains(q, oic));

        if (StatusFilter.SelectedIndex > 0 && StatusFilter.SelectedItem is string st)
            jobs = jobs.Where(j => string.Equals(j.Status, st, oic));
        if (CategoryFilter.SelectedIndex > 0 && CategoryFilter.SelectedItem is string cat)
            jobs = jobs.Where(j => string.Equals(j.Category, cat, oic));
        if (RankFilter.SelectedIndex > 0 && RankFilter.SelectedItem is string rk)
            jobs = jobs.Where(j => string.Equals(j.ResponsibleRank, rk, oic));

        // Completion filter: 1 = active only, 2 = completed only, else all.
        int ci = CompletionFilter.SelectedIndex;
        if (ci == 1) jobs = jobs.Where(j => !j.IsCompleted);
        else if (ci == 2) jobs = jobs.Where(j => j.IsCompleted);

        // Due/overdue excludes completed (a completed job is no longer "due").
        if (DueSoonBtn.IsChecked == true)
            jobs = jobs.Where(j => !j.IsCompleted && j.DaysUntilDue(today) is int d && d <= DueSoonDays);
        if (NotifyOnlyBtn.IsChecked == true)
            jobs = jobs.Where(j => j.Notify);

        return ApplySort(jobs, today);
    }

    private IEnumerable<ShipJob> ApplySort(IEnumerable<ShipJob> jobs, DateTime today)
    {
        bool d = _sortDescending;
        IOrderedEnumerable<ShipJob> ordered = _sortColumn switch
        {
            "Job No." => OrderStr(jobs, j => j.JobNo, d),
            "Title" => OrderStr(jobs, j => j.Title, d),
            "Interval" => OrderStr(jobs, j => j.Interval, d),
            "Status" => OrderStr(jobs, j => j.Status, d),
            "Due Status" => OrderStr(jobs, j => j.DueStatus, d),
            "Category" => OrderStr(jobs, j => j.Category, d),
            "Responsible" => OrderStr(jobs, j => j.ResponsibleRank, d),
            "Function" => OrderStr(jobs, j => j.FunctionDescription, d),
            "Done" => d ? jobs.OrderByDescending(j => j.IsCompleted) : jobs.OrderBy(j => j.IsCompleted),
            "Notify" => d ? jobs.OrderByDescending(j => j.Notify) : jobs.OrderBy(j => j.Notify),
            // Default "Due": completed sink to the bottom, then soonest/overdue first.
            _ => d
                ? jobs.OrderByDescending(j => j.IsCompleted).ThenByDescending(j => j.DaysUntilDue(today) ?? int.MaxValue)
                : jobs.OrderBy(j => j.IsCompleted).ThenBy(j => j.DaysUntilDue(today) ?? int.MaxValue),
        };
        return ordered.ThenBy(j => j.JobNo, StringComparer.OrdinalIgnoreCase);
    }

    private static IOrderedEnumerable<ShipJob> OrderStr(IEnumerable<ShipJob> jobs, Func<ShipJob, string> key, bool desc) =>
        desc ? jobs.OrderByDescending(key, StringComparer.OrdinalIgnoreCase)
             : jobs.OrderBy(key, StringComparer.OrdinalIgnoreCase);

    private void BuildView()
    {
        if (_vessel == null) { JobsList.ItemsSource = null; SummaryText.Text = "No ship selected."; return; }
        var today = DateTime.Today;
        var rows = Filtered().Select(j =>
        {
            var (info, brush) = DueInfo(j, today);
            return new JobRow { Job = j, DueInfo = info, DueBrush = brush };
        }).ToList();
        JobsList.ItemsSource = rows;
        UpdateSummary();
        UpdateNotifications();
    }

    private void UpdateSummary()
    {
        if (_vessel == null) return;
        var today = DateTime.Today;
        var all = _vessel.Jobs;
        int total = all.Count;
        if (total == 0) { SummaryText.Text = "No work orders imported yet for this ship. Click “Import Shippalm (.xlsx)...”."; return; }
        // Completed jobs don't count as overdue / due.
        int overdue = all.Count(j => !j.IsCompleted && j.DaysUntilDue(today) is int d && d < 0);
        int due30 = all.Count(j => !j.IsCompleted && j.DaysUntilDue(today) is int d && d >= 0 && d <= 30);
        int due90 = all.Count(j => !j.IsCompleted && j.DaysUntilDue(today) is int d && d >= 0 && d <= 90);
        int completed = all.Count(j => j.IsCompleted);
        int notify = all.Count(j => j.Notify);
        int shown = (JobsList.ItemsSource as System.Collections.ICollection)?.Count ?? 0;
        var byCat = all.GroupBy(j => string.IsNullOrWhiteSpace(j.Category) ? "(none)" : j.Category)
            .OrderByDescending(g => g.Count()).Take(5)
            .Select(g => $"{g.Key} {g.Count()}");
        SummaryText.Text =
            $"⚙ {total} work orders   ·   ⚠ {overdue} overdue   ·   {due30} due ≤30d   ·   {due90} due ≤90d   ·   ✓ {completed} completed   ·   🔔 {notify} notify-on   ·   showing {shown}\n" +
            $"By category: {string.Join("   ", byCat)}";
    }

    private static (string info, Brush brush) DueInfo(ShipJob j, DateTime today)
    {
        if (j.IsCompleted)
            return (string.IsNullOrWhiteSpace(j.CompletedDate) ? "✓ completed" : $"✓ completed {j.CompletedDate}", GreenBrush);
        var days = j.DaysUntilDue(today);
        if (days == null) return (string.IsNullOrWhiteSpace(j.DueDate) ? "" : j.DueDate, GrayBrush);
        int d = days.Value;
        if (d < 0) return ($"OVERDUE {-d}d  ({j.DueDate})", RedBrush);
        if (d == 0) return ($"DUE TODAY  ({j.DueDate})", RedBrush);
        if (d <= 30) return ($"in {d}d  ({j.DueDate})", OrangeBrush);
        if (d <= 90) return ($"in {d}d  ({j.DueDate})", AmberBrush);
        return ($"{j.DueDate}  (in {d}d)", GreenBrush);
    }

    // ---- Notify choices ----
    private void NotifyToggle_Click(object sender, RoutedEventArgs e)
    {
        // Two-way binding already updated Job.Notify. Persist via the DEBOUNCED save so ticking many
        // boxes quickly doesn't rewrite the whole data file on every click (it saves once you pause).
        _repo?.MarkDirty();
        // When the "notify on only" filter is active the row's membership just changed, so re-run the
        // filter; otherwise only the notify count changed, so a summary + notifications refresh is enough.
        if (NotifyOnlyBtn.IsChecked == true) BuildView();
        else { UpdateSummary(); UpdateNotifications(); }
    }

    private void NotifyAllOn_Click(object sender, RoutedEventArgs e) => SetNotifyForShown(true);
    private void NotifyAllOff_Click(object sender, RoutedEventArgs e) => SetNotifyForShown(false);

    private void SetNotifyForShown(bool on)
    {
        if (_repo == null || JobsList.ItemsSource is not IEnumerable<JobRow> rows) return;
        var list = rows.ToList();
        if (list.Count == 0) return;
        foreach (var r in list) r.Job.Notify = on;
        _repo.Save();
        BuildView();   // membership may change under the "notify on only" filter; re-run it + refresh counts
        StatusHint($"Notifications turned {(on ? "ON" : "OFF")} for {list.Count} shown job(s).");
    }

    // ---- Completion ----
    private void CompletedToggle_Click(object sender, RoutedEventArgs e)
    {
        // Two-way binding already flipped Job.IsCompleted; stamp/clear the completed date and persist.
        if (sender is CheckBox cb && cb.DataContext is JobRow r)
            r.Job.CompletedDate = r.Job.IsCompleted ? DateTime.Today.ToString("yyyy-MM-dd") : "";
        _repo?.MarkDirty();
        BuildView();   // completion affects strike-through, due colour, counts, sort and filters
    }

    private void MarkCompleted_Click(object sender, RoutedEventArgs e) => SetCompletedForTarget(true);
    private void MarkActive_Click(object sender, RoutedEventArgs e) => SetCompletedForTarget(false);

    private void SetCompletedForTarget(bool done)
    {
        if (_repo == null) return;
        var target = TargetRows();
        if (target.Count == 0) { StatusHint("No work orders to update — select rows, or clear filters so some are shown."); return; }
        var today = DateTime.Today.ToString("yyyy-MM-dd");
        foreach (var j in target) { j.IsCompleted = done; j.CompletedDate = done ? today : ""; }
        _repo.Save();
        BuildView();
        StatusHint($"Marked {target.Count} work order(s) {(done ? "completed" : "active")}.");
    }

    // ---- Deletion ----
    private void Delete_Click(object sender, RoutedEventArgs e)
    {
        if (_repo == null || _vessel == null) return;
        var sel = JobsList.SelectedItems.Cast<JobRow>().Select(r => r.Job).ToList();
        if (sel.Count == 0) { StatusHint("Select one or more work orders to delete."); return; }
        if (MessageBox.Show(Window.GetWindow(this),
                $"Delete {sel.Count} work order(s) from {_vessel.Name}? This is permanent (re-import to restore).",
                "Delete work orders", MessageBoxButton.YesNo, MessageBoxImage.Warning) != MessageBoxResult.Yes) return;
        foreach (var j in sel) _vessel.Jobs.Remove(j);
        _repo.Save();
        PopulateFilters();
        BuildView();
        StatusHint($"Deleted {sel.Count} work order(s) from {_vessel.Name}.");
    }

    // ---- Notify (selected / shown) ----
    private void NotifySelectedOn_Click(object sender, RoutedEventArgs e) => SetNotifyForTarget(true);
    private void NotifySelectedOff_Click(object sender, RoutedEventArgs e) => SetNotifyForTarget(false);

    private void SetNotifyForTarget(bool on)
    {
        if (_repo == null) return;
        var target = TargetRows();
        if (target.Count == 0) return;
        foreach (var j in target) j.Notify = on;
        _repo.Save();
        BuildView();
        StatusHint($"Notifications turned {(on ? "ON" : "OFF")} for {target.Count} work order(s).");
    }

    /// <summary>The selected rows, or (if nothing is selected) every currently-shown row.</summary>
    private List<ShipJob> TargetRows()
    {
        var sel = JobsList.SelectedItems.Cast<JobRow>().Select(r => r.Job).ToList();
        if (sel.Count > 0) return sel;
        return (JobsList.ItemsSource as IEnumerable<JobRow>)?.Select(r => r.Job).ToList() ?? new List<ShipJob>();
    }

    private void StatusHint(string msg)
    {
        if (Window.GetWindow(this)?.FindName("StatusBlock") is TextBlock sb) sb.Text = msg;
    }
}

/// <summary>Row wrapper: the underlying <see cref="ShipJob"/> plus a computed due-status label/colour.</summary>
public sealed class JobRow
{
    public ShipJob Job { get; init; } = null!;
    public string DueInfo { get; init; } = "";
    public Brush DueBrush { get; init; } = Brushes.Gray;
}
