using System;
using System.Collections.Generic;
using System.Linq;
using System.Windows.Controls;
using AA.Models;
using AA.Services;

namespace AA.Views;

/// <summary>The global Ports Database tab: every port any vessel has called (aggregated from each
/// vessel's imported ports), and — per selected port — which vessels called and when.</summary>
public partial class PortsPage : UserControl
{
    private AppRepository? _repo;

    public PortsPage() { InitializeComponent(); }

    public void Init(AppRepository repo) { _repo = repo; Refresh(); }

    private Port? Selected => PortList.SelectedItem as Port;

    public void Refresh()
    {
        if (_repo == null) return;
        var keepId = Selected?.Id;
        var q = SearchBox.Text?.Trim() ?? "";

        IEnumerable<Port> ports = _repo.Data.Ports;
        if (q.Length > 0)
            ports = ports.Where(p =>
                p.Name.Contains(q, StringComparison.OrdinalIgnoreCase) ||
                p.Country.Contains(q, StringComparison.OrdinalIgnoreCase) ||
                p.UnLocode.Contains(q, StringComparison.OrdinalIgnoreCase));

        var list = ports.OrderBy(p => p.Name, StringComparer.OrdinalIgnoreCase).ToList();
        PortList.ItemsSource = list;
        if (keepId is Guid id)
        {
            var keep = list.FirstOrDefault(p => p.Id == id);
            if (keep != null) PortList.SelectedItem = keep;
        }

        int totalPorts = _repo.Data.Ports.Count;
        int totalVisits = _repo.Data.Ports.Sum(p => p.Visits.Count);
        StatusText.Text = totalPorts == 0
            ? "No ports yet. Import a ports-of-call list on any vessel's “Ports” tab."
            : $"{totalPorts} port(s)  ·  {totalVisits} visit(s)" + (list.Count != totalPorts ? $"  ·  showing {list.Count}" : "");
        ShowVisits();
    }

    private void Search_Changed(object sender, TextChangedEventArgs e) => Refresh();
    private void PortList_SelectionChanged(object sender, SelectionChangedEventArgs e) => ShowVisits();

    private void ShowVisits()
    {
        var p = Selected;
        if (p == null)
        {
            Header.Text = "Select a port to see the vessels that called.";
            VisitList.ItemsSource = null;
            return;
        }
        var visits = p.Visits
            .OrderByDescending(v => v.ArrivalValue ?? DateTime.MinValue).ThenByDescending(v => v.ArrivalTime)
            .ToList();
        Header.Text = $"⚓ {p.Display}   —   {visits.Count} visit(s)";
        VisitList.ItemsSource = visits;
    }
}
