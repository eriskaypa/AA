using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Data;
using AA.Models;
using AA.Services;
using Microsoft.Win32;

namespace AA.Views;

/// <summary>Interactive crew-schedule/timeline builder: add dated entries (a Task, Procedure, Equipment
/// or free note), see them on a date-grouped timeline, and save / apply / export / import reusable
/// schedules. Hosted in the crew editor's Schedule tab.</summary>
public partial class ScheduleBuilderControl : UserControl
{
    private CrewMember? _crew;
    private AppRepository? _repo;
    private bool _suppress;
    private Guid? _pendingRefId;   // set when the user picks an item to schedule

    public ScheduleBuilderControl()
    {
        InitializeComponent();
        KindBox.ItemsSource = Enum.GetValues(typeof(ScheduleKind));
        KindBox.SelectedItem = ScheduleKind.Note;
    }

    public void Bind(CrewMember crew, AppRepository repo)
    {
        _crew = crew;
        _repo = repo;
        _suppress = true;
        DateBox.SelectedDate = DateTime.Today;
        var choices = new List<VesselChoice> { new() { Display = "(none)", Vessel = null } };
        choices.AddRange(repo.Data.Vessels.Select(v => new VesselChoice { Display = v.Name.Length > 0 ? v.Name : "(unnamed)", Vessel = v }));
        VesselBox.ItemsSource = choices;
        VesselBox.DisplayMemberPath = nameof(VesselChoice.Display);
        VesselBox.SelectedItem = choices.FirstOrDefault(c => c.Vessel?.Id == crew.ScheduleVesselId) ?? choices[0];
        _suppress = false;
        UpdatePickButton();
        Refresh();
    }

    private sealed class Row
    {
        public required ScheduleEntry Entry { get; init; }
        public required string DateGroup { get; init; }
        public required string GroupSort { get; init; }
        public required string TimeSort { get; init; }
    }

    private void Refresh()
    {
        if (_crew == null) return;
        var today = DateTime.Today;
        var rows = _crew.Schedule.Select(e =>
        {
            var w = e.When;
            string group = w == null ? "(no date)"
                : w.Value.Date == today ? "Today"
                : w.Value.Date == today.AddDays(1) ? "Tomorrow"
                : w.Value.ToString("ddd, yyyy-MM-dd");
            return new Row
            {
                Entry = e,
                DateGroup = group,
                GroupSort = w?.ToString("yyyy-MM-dd") ?? "￿",
                TimeSort = e.Time.Length > 0 ? e.Time : "00:00"
            };
        }).ToList();

        var view = new ListCollectionView(rows);
        view.SortDescriptions.Add(new SortDescription(nameof(Row.GroupSort), ListSortDirection.Ascending));
        view.SortDescriptions.Add(new SortDescription(nameof(Row.TimeSort), ListSortDirection.Ascending));
        view.GroupDescriptions.Add(new PropertyGroupDescription(nameof(Row.DateGroup)));
        Timeline.ItemsSource = view;

        int done = _crew.Schedule.Count(e => e.Done);
        CountText.Text = _crew.Schedule.Count == 0
            ? "No entries yet — pick a date, choose what, and click “+ Add”."
            : $"{_crew.Schedule.Count} entr{(_crew.Schedule.Count == 1 ? "y" : "ies")}" + (done > 0 ? $" · {done} done" : "");
    }

    // ---- Interactive add ----
    private void Kind_Changed(object sender, SelectionChangedEventArgs e) { _pendingRefId = null; UpdatePickButton(); }

    private void UpdatePickButton()
    {
        var kind = (ScheduleKind?)KindBox.SelectedItem ?? ScheduleKind.Note;
        PickBtn.IsEnabled = kind != ScheduleKind.Note;
    }

    private void Pick_Click(object sender, RoutedEventArgs e)
    {
        if (_repo == null) return;
        var kind = (ScheduleKind?)KindBox.SelectedItem ?? ScheduleKind.Note;
        IEnumerable<HierarchyItem> src = kind switch
        {
            ScheduleKind.Task => _repo.Data.Tasks,
            ScheduleKind.Procedure => _repo.Data.Procedures,
            ScheduleKind.Equipment => _repo.Data.Equipment,
            _ => Enumerable.Empty<HierarchyItem>()
        };
        var options = src.OrderBy(i => i.Name, StringComparer.OrdinalIgnoreCase)
            .Select(i => new PickerItem { Display = i.Name, Tag = i }).ToList();
        if (options.Count == 0)
        {
            MessageBox.Show(Window.GetWindow(this), $"No {kind} items exist yet to schedule.", "Pick item", MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }
        var dlg = new ItemPickerWindow($"Pick a {kind} to schedule", options, Array.Empty<object>(), singleSelect: true) { Owner = Window.GetWindow(this) };
        if (dlg.ShowDialog() != true || dlg.SelectedTags.FirstOrDefault() is not HierarchyItem item) return;
        TitleBox.Text = item.Name;
        _pendingRefId = item.Id;
    }

    private void Add_Click(object sender, RoutedEventArgs e)
    {
        if (_crew == null || _repo == null) return;
        var kind = (ScheduleKind?)KindBox.SelectedItem ?? ScheduleKind.Note;
        var title = TitleBox.Text?.Trim() ?? "";
        if (title.Length == 0) { MessageBox.Show(Window.GetWindow(this), "Type what to schedule (or pick an item).", "Add entry", MessageBoxButton.OK, MessageBoxImage.Information); return; }
        var entry = new ScheduleEntry
        {
            Title = title,
            Kind = kind,
            RefId = kind == ScheduleKind.Note ? null : _pendingRefId,
            Date = DateBox.SelectedDate?.ToString("yyyy-MM-dd") ?? "",
            Time = NormTime(TimeBox.Text)
        };
        _crew.Schedule.Add(entry);
        _repo.Save();
        TitleBox.Clear();
        _pendingRefId = null;
        Refresh();
    }

    private static string NormTime(string? s)
    {
        s = (s ?? "").Trim();
        var m = System.Text.RegularExpressions.Regex.Match(s, @"^(\d{1,2}):(\d{2})$");
        return m.Success ? $"{int.Parse(m.Groups[1].Value):00}:{m.Groups[2].Value}" : "";
    }

    // ---- Row actions ----
    private void Done_Click(object sender, RoutedEventArgs e) { _repo?.MarkDirty(); Refresh(); }

    private void Edit_Click(object sender, RoutedEventArgs e)
    {
        if (_repo == null || (sender as FrameworkElement)?.Tag is not Guid id) return;
        var entry = _crew?.Schedule.FirstOrDefault(x => x.Id == id);
        if (entry == null) return;
        var p = new PromptWindow("Edit entry", "Title:", entry.Title) { Owner = Window.GetWindow(this) };
        if (p.ShowDialog() == true && !string.IsNullOrWhiteSpace(p.Value)) { entry.Title = p.Value.Trim(); _repo.Save(); Refresh(); }
    }

    private void Delete_Click(object sender, RoutedEventArgs e)
    {
        if (_repo == null || _crew == null || (sender as FrameworkElement)?.Tag is not Guid id) return;
        var entry = _crew.Schedule.FirstOrDefault(x => x.Id == id);
        if (entry == null) return;
        _crew.Schedule.Remove(entry);
        _repo.Save();
        Refresh();
    }

    // ---- Vessel link ----
    private sealed class VesselChoice { public string Display { get; init; } = ""; public Vessel? Vessel { get; init; } }

    private void Vessel_Changed(object sender, SelectionChangedEventArgs e)
    {
        if (_suppress || _crew == null || _repo == null) return;
        _crew.ScheduleVesselId = (VesselBox.SelectedItem as VesselChoice)?.Vessel?.Id;
        _repo.Save();
    }

    // ---- Save / apply / export / import ----
    private void Save_Click(object sender, RoutedEventArgs e)
    {
        if (_crew == null || _repo == null) return;
        if (_crew.Schedule.Count == 0) { MessageBox.Show(Window.GetWindow(this), "Add some entries first.", "Save schedule", MessageBoxButton.OK, MessageBoxImage.Information); return; }
        var p = new PromptWindow("Save schedule", "Name for this reusable schedule:", _crew.FullName) { Owner = Window.GetWindow(this) };
        if (p.ShowDialog() != true || string.IsNullOrWhiteSpace(p.Value)) return;
        var t = ScheduleService.CaptureFromCrew(p.Value, _crew, _repo.Data);
        _repo.Data.ScheduleTemplates.Add(t);
        _repo.LogAdded("Schedule", t.Name, $"{t.Entries.Count} entr{(t.Entries.Count == 1 ? "y" : "ies")}");
        _repo.Save();
        MessageBox.Show(Window.GetWindow(this), $"Saved '{t.Name}'. You can apply it to any crew member.", "Save schedule", MessageBoxButton.OK, MessageBoxImage.Information);
    }

    private void Apply_Click(object sender, RoutedEventArgs e)
    {
        if (_crew == null || _repo == null) return;
        if (_repo.Data.ScheduleTemplates.Count == 0) { MessageBox.Show(Window.GetWindow(this), "No saved schedules yet. Build one and click 'Save as...'.", "Apply schedule", MessageBoxButton.OK, MessageBoxImage.Information); return; }
        var options = _repo.Data.ScheduleTemplates.Select(t => new PickerItem { Display = t.Display, Tag = t }).ToList();
        var dlg = new ItemPickerWindow("Apply a saved schedule", options, Array.Empty<object>(), singleSelect: true) { Owner = Window.GetWindow(this) };
        if (dlg.ShowDialog() != true || dlg.SelectedTags.FirstOrDefault() is not ScheduleTemplate t) return;
        ApplyTemplate(t);
    }

    private void ApplyTemplate(ScheduleTemplate t)
    {
        if (_crew == null || _repo == null) return;
        var how = MessageBox.Show(Window.GetWindow(this),
            $"Apply '{t.Name}' ({t.Entries.Count} entries) to {_crew.FullName}.\n\nYes = replace this crew's schedule\nNo = append\nCancel = nothing",
            "Apply schedule", MessageBoxButton.YesNoCancel, MessageBoxImage.Question);
        if (how == MessageBoxResult.Cancel) return;
        int n = ScheduleService.ApplyToCrew(t, _crew, replace: how == MessageBoxResult.Yes);
        _repo.Save();
        Bind(_crew, _repo);   // reflect the (possibly changed) vessel link + entries
        MessageBox.Show(Window.GetWindow(this), $"Applied {n} entr{(n == 1 ? "y" : "ies")} to {_crew.FullName}.", "Apply schedule", MessageBoxButton.OK, MessageBoxImage.Information);
    }

    private void Export_Click(object sender, RoutedEventArgs e)
    {
        if (_crew == null || _repo == null) return;
        if (_crew.Schedule.Count == 0) { MessageBox.Show(Window.GetWindow(this), "No schedule to export.", "Export", MessageBoxButton.OK, MessageBoxImage.Information); return; }
        var dlg = new SaveFileDialog { Title = "Export schedule", Filter = "AA schedule (*.aasched.json)|*.aasched.json|JSON (*.json)|*.json", FileName = $"Schedule-{Sanitize(_crew.FullName)}.aasched.json", DefaultExt = ".aasched.json" };
        if (dlg.ShowDialog() != true) return;
        try
        {
            var t = ScheduleService.CaptureFromCrew(_crew.FullName + " schedule", _crew, _repo.Data);
            ScheduleService.ExportJson(t, dlg.FileName);
            MessageBox.Show(Window.GetWindow(this), $"Exported to:\n{dlg.FileName}", "Export complete", MessageBoxButton.OK, MessageBoxImage.Information);
        }
        catch (Exception ex) { MessageBox.Show(Window.GetWindow(this), $"Could not export:\n\n{ex.Message}", "Export failed", MessageBoxButton.OK, MessageBoxImage.Error); }
    }

    private void Import_Click(object sender, RoutedEventArgs e)
    {
        if (_crew == null || _repo == null) return;
        var dlg = new OpenFileDialog { Title = "Import schedule", Filter = "AA schedule (*.aasched.json;*.json)|*.aasched.json;*.json|All files (*.*)|*.*" };
        if (dlg.ShowDialog() != true) return;
        try
        {
            var t = ScheduleService.ImportJson(dlg.FileName);
            _repo.Data.ScheduleTemplates.Add(t);   // keep it as a reusable saved schedule too
            _repo.Save();
            ApplyTemplate(t);
        }
        catch (Exception ex) { MessageBox.Show(Window.GetWindow(this), $"Could not import the schedule:\n\n{ex.Message}", "Import failed", MessageBoxButton.OK, MessageBoxImage.Error); }
    }

    private static string Sanitize(string s)
    {
        foreach (var c in System.IO.Path.GetInvalidFileNameChars()) s = s.Replace(c, '_');
        return string.IsNullOrWhiteSpace(s) ? "crew" : s.Trim();
    }
}
