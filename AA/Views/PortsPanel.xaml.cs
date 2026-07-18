using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using AA.Models;
using AA.Services;
using Microsoft.Win32;

namespace AA.Views;

/// <summary>Per-vessel ports of call: import a ports list (two layouts auto-detected), sort/filter, and
/// delete. Imports also feed the global ports database (the vessel + arrival for each port).</summary>
public partial class PortsPanel : UserControl
{
    private AppRepository? _repo;
    private Vessel? _vessel;
    private string _sortColumn = "Arrival";
    private bool _sortDescending = true;   // most-recent first by default

    public PortsPanel() { InitializeComponent(); }

    public void Load(Vessel vessel, AppRepository repo)
    {
        _vessel = vessel;
        _repo = repo;
        BuildView();
    }

    private async void Import_Click(object sender, RoutedEventArgs e)
    {
        if (_repo == null || _vessel == null) return;
        var dlg = new OpenFileDialog
        {
            Title = $"Import ports of call for {_vessel.Name}",
            Filter = "Excel workbook (*.xlsx)|*.xlsx|All files (*.*)|*.*"
        };
        if (dlg.ShowDialog() != true) return;
        try
        {
            Mouse.OverrideCursor = Cursors.Wait;
            var result = await Task.Run(() => PortCallReader.Read(dlg.FileName));
            Mouse.OverrideCursor = null;

            // If the file names a different vessel, confirm the user really wants it on THIS vessel.
            if (result.VesselName.Length > 0 &&
                !result.VesselName.Equals(_vessel.Name, StringComparison.OrdinalIgnoreCase))
            {
                var ok = MessageBox.Show(Window.GetWindow(this),
                    $"This file lists vessel \"{result.VesselName}\", but you're importing into \"{_vessel.Name}\".\n\nImport these {result.Calls.Count} port call(s) for {_vessel.Name} anyway?",
                    "Different vessel", MessageBoxButton.YesNo, MessageBoxImage.Question);
                if (ok != MessageBoxResult.Yes) return;
            }

            var (added, updated, visits) = PortsService.Apply(_repo.Data, _vessel, result.Calls);
            _repo.LogAdded("Ports import", $"{added} new, {updated} updated", $"{_vessel.Name} · {result.Format}");
            _repo.Save();
            BuildView();
            StatusHint($"Imported {result.Calls.Count} port(s) for {_vessel.Name} ({added} new, {updated} updated) — {result.Format}. {visits} new visit(s) in the ports database.");
        }
        catch (Exception ex)
        {
            Mouse.OverrideCursor = null;
            MessageBox.Show(Window.GetWindow(this), $"Could not import the ports file:\n\n{ex.Message}",
                "Import failed", MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }

    private void Export_Click(object sender, RoutedEventArgs e)
    {
        if (_vessel == null) return;
        if (_vessel.PortCalls.Count == 0)
        {
            MessageBox.Show(Window.GetWindow(this), "No ports to export for this vessel.", "Export", MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }
        var safe = string.Concat((_vessel.Name ?? "vessel").Select(ch => System.IO.Path.GetInvalidFileNameChars().Contains(ch) ? '_' : ch));
        var dlg = new SaveFileDialog { Title = "Export ports of call", Filter = "Excel workbook (*.xlsx)|*.xlsx", FileName = $"Ports-{safe}.xlsx", DefaultExt = ".xlsx", AddExtension = true };
        if (dlg.ShowDialog() != true) return;
        try
        {
            Mouse.OverrideCursor = Cursors.Wait;
            PortsService.Export(_vessel, dlg.FileName);
            Mouse.OverrideCursor = null;
            StatusHint($"Exported {_vessel.PortCalls.Count} port(s) for {_vessel.Name}.");
            try { System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(dlg.FileName) { UseShellExecute = true }); } catch { }
        }
        catch (Exception ex)
        {
            Mouse.OverrideCursor = null;
            MessageBox.Show(Window.GetWindow(this), $"Could not export:\n\n{ex.Message}", "Export failed", MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }

    private void Delete_Click(object sender, RoutedEventArgs e)
    {
        if (_repo == null || _vessel == null) return;
        var sel = PortsList.SelectedItems.Cast<PortCall>().ToList();
        if (sel.Count == 0) { StatusHint("Select one or more ports to delete."); return; }
        if (MessageBox.Show(Window.GetWindow(this), $"Delete {sel.Count} port call(s) from {_vessel.Name}? Their visit is also removed from the ports database.",
                "Delete ports", MessageBoxButton.YesNo, MessageBoxImage.Warning) != MessageBoxResult.Yes) return;
        foreach (var c in sel) PortsService.RemoveCall(_repo.Data, _vessel, c);
        _repo.Save();
        BuildView();
        StatusHint($"Deleted {sel.Count} port call(s).");
    }

    private void Search_Changed(object sender, TextChangedEventArgs e) => BuildView();

    private void Header_Click(object sender, RoutedEventArgs e)
    {
        if (e.OriginalSource is not GridViewColumnHeader h || h.Column?.Header is not string col || col.Length == 0) return;
        if (_sortColumn == col) _sortDescending = !_sortDescending;
        else { _sortColumn = col; _sortDescending = false; }
        BuildView();
    }

    private void BuildView()
    {
        if (_vessel == null) { PortsList.ItemsSource = null; SummaryText.Text = "No vessel selected."; return; }
        IEnumerable<PortCall> calls = _vessel.PortCalls;
        var q = SearchBox.Text?.Trim() ?? "";
        if (q.Length > 0)
            calls = calls.Where(c =>
                c.PortName.Contains(q, StringComparison.OrdinalIgnoreCase) ||
                c.Country.Contains(q, StringComparison.OrdinalIgnoreCase) ||
                c.UnLocode.Contains(q, StringComparison.OrdinalIgnoreCase));

        calls = _sortColumn switch
        {
            "Port" => Order(calls, c => c.PortName),
            "Country" => Order(calls, c => c.Country),
            "UN/LOCODE" => Order(calls, c => c.UnLocode),
            "Departure" => Order(calls, c => c.DepartureDate + " " + c.DepartureTime),
            "Sec P" => Order(calls, c => c.SecurityLevelPort),
            "Sec V" => Order(calls, c => c.SecurityLevelVessel),
            "SSP" => Order(calls, c => c.SspFollowed),
            "Port Facility" => Order(calls, c => c.PortFacility),
            _ => _sortDescending
                ? calls.OrderByDescending(c => c.ArrivalValue ?? DateTime.MinValue).ThenByDescending(c => c.ArrivalTime)
                : calls.OrderBy(c => c.ArrivalValue ?? DateTime.MinValue).ThenBy(c => c.ArrivalTime),
        };

        var list = calls.ToList();
        PortsList.ItemsSource = list;
        int total = _vessel.PortCalls.Count;
        SummaryText.Text = total == 0
            ? "No ports imported yet for this vessel. Click “Import ports (.xlsx)...”."
            : $"⚓ {total} port call(s)" + (list.Count != total ? $"  ·  showing {list.Count}" : "")
              + (_vessel.PortCalls.Count > 0 ? $"  ·  latest: {_vessel.PortCalls.OrderByDescending(c => c.ArrivalValue ?? DateTime.MinValue).First().DisplayName} ({_vessel.PortCalls.OrderByDescending(c => c.ArrivalValue ?? DateTime.MinValue).First().ArrivalDate})" : "");
    }

    private System.Linq.IOrderedEnumerable<PortCall> Order(IEnumerable<PortCall> src, Func<PortCall, string> key) =>
        _sortDescending ? src.OrderByDescending(key, StringComparer.OrdinalIgnoreCase) : src.OrderBy(key, StringComparer.OrdinalIgnoreCase);

    private void StatusHint(string msg)
    {
        if (Window.GetWindow(this)?.FindName("StatusBlock") is TextBlock sb) sb.Text = msg;
    }
}
