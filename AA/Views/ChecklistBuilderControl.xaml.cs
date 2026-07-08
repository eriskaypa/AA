using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using AA.Models;
using AA.Services;

namespace AA.Views;

/// <summary>Reusable "comprehensive checklist builder" — bulk entry, reorder, per-item full editor
/// (deadline / done / notes / files), and save/load of reusable checklists to the database. Operates on
/// any <see cref="ObservableCollection{ChecklistStep}"/> so procedures and crew members share one builder.</summary>
public partial class ChecklistBuilderControl : UserControl
{
    private ObservableCollection<ChecklistStep>? _steps;
    private AppRepository? _repo;
    private string _ownerName = "";
    private string _logKind = "Checklist step";

    public ChecklistBuilderControl() { InitializeComponent(); }

    /// <summary>Bind the builder to a checklist. <paramref name="ownerName"/> is used in the activity log;
    /// <paramref name="logKind"/> labels the kind of item (e.g. "Checklist step", "Crew checklist item").</summary>
    public void Bind(ObservableCollection<ChecklistStep> steps, AppRepository repo, string ownerName, string logKind = "Checklist step")
    {
        _steps = steps;
        _repo = repo;
        _ownerName = ownerName ?? "";
        _logKind = logKind;
        RefreshList();
    }

    private void RefreshList()
    {
        if (_steps == null) return;
        var keepIds = StepsList.SelectedItems.Cast<ChecklistStep>().Select(s => s.Id).ToHashSet();
        StepsList.ItemsSource = null;
        StepsList.ItemsSource = _steps;
        if (keepIds.Count > 0)
        {
            StepsList.SelectedItems.Clear();
            foreach (var s in _steps)
                if (keepIds.Contains(s.Id)) StepsList.SelectedItems.Add(s);
        }
    }

    private void SelectByReference(IEnumerable<ChecklistStep> items)
    {
        StepsList.SelectedItems.Clear();
        ChecklistStep? first = null;
        foreach (var s in items) { StepsList.SelectedItems.Add(s); first ??= s; }
        if (first != null) StepsList.ScrollIntoView(first);
    }

    // ---- Bulk / add ----
    private void AddAll_Click(object sender, RoutedEventArgs e)
    {
        if (_steps == null || _repo == null) return;
        var lines = (BulkBox.Text ?? "").Replace("\r\n", "\n").Split('\n')
            .Select(l => l.Trim()).Where(l => l.Length > 0).ToList();
        if (lines.Count == 0) return;
        if (ReplaceBox.IsChecked == true) _steps.Clear();
        foreach (var line in lines) _steps.Add(new ChecklistStep { Title = line });
        BulkBox.Clear();
        _repo.LogAdded(_logKind, $"{lines.Count} added (bulk)", _ownerName);
        _repo.MarkDirty();
        RefreshList();
    }

    private void ClearText_Click(object sender, RoutedEventArgs e) => BulkBox.Clear();

    private void AddOne_Click(object sender, RoutedEventArgs e) => AddAt(_steps?.Count ?? 0);

    private void InsertBefore_Click(object sender, RoutedEventArgs e)
    {
        var idx = FirstSelectedIndex();
        AddAt(idx < 0 ? 0 : idx);
    }

    private void InsertAfter_Click(object sender, RoutedEventArgs e)
    {
        var idx = LastSelectedIndex();
        AddAt(idx < 0 ? (_steps?.Count ?? 0) : idx + 1);
    }

    private void AddAt(int index)
    {
        if (_steps == null || _repo == null) return;
        var p = new PromptWindow("New item", "Title:") { Owner = Window.GetWindow(this) };
        if (p.ShowDialog() != true || string.IsNullOrWhiteSpace(p.Value)) return;
        index = Math.Clamp(index, 0, _steps.Count);
        var step = new ChecklistStep { Title = p.Value };
        _steps.Insert(index, step);
        _repo.LogAdded(_logKind, step.Title, _ownerName);
        _repo.MarkDirty();
        RefreshList();
        SelectByReference(new[] { step });
    }

    // ---- Full per-item editor ----
    private void StepsList_DoubleClick(object sender, MouseButtonEventArgs e) => EditOne_Click(sender, e);

    private void EditOne_Click(object sender, RoutedEventArgs e)
    {
        if (_repo == null || StepsList.SelectedItem is not ChecklistStep st) return;
        new ChecklistStepEditorWindow(st, _repo) { Owner = Window.GetWindow(this) }.ShowDialog();
        _repo.FlushIfDirty();
        RefreshList();
    }

    // ---- Reorder ----
    private void Up_Click(object sender, RoutedEventArgs e)
    {
        if (_steps == null || _repo == null) return;
        var picks = SelectedIndicesAscending();
        if (picks.Count == 0 || picks[0] == 0) return;
        foreach (var i in picks) _steps.Move(i, i - 1);
        _repo.MarkDirty();
        RefreshList();
    }

    private void Down_Click(object sender, RoutedEventArgs e)
    {
        if (_steps == null || _repo == null) return;
        var picks = SelectedIndicesAscending();
        if (picks.Count == 0 || picks[^1] == _steps.Count - 1) return;
        foreach (var i in picks.AsEnumerable().Reverse()) _steps.Move(i, i + 1);
        _repo.MarkDirty();
        RefreshList();
    }

    private void MoveTo_Click(object sender, RoutedEventArgs e)
    {
        if (_steps == null) return;
        var picks = StepsList.SelectedItems.Cast<ChecklistStep>().ToList();
        if (picks.Count == 0) return;
        var selectedSet = picks.ToHashSet();
        var options = new List<PickerItem> { new() { Display = "(Move to top)", Tag = (object)0 } };
        for (int i = 0; i < _steps.Count; i++)
        {
            var s = _steps[i];
            if (selectedSet.Contains(s)) continue;
            options.Add(new PickerItem { Display = $"Before: {Shorten(s.Title, 60)}", Tag = (object)i });
        }
        options.Add(new PickerItem { Display = "(Move to bottom)", Tag = (object)_steps.Count });

        var dlg = new ItemPickerWindow(
            $"Move {picks.Count} item{(picks.Count == 1 ? "" : "s")} to...",
            options, Array.Empty<object>(), singleSelect: true)
        { Owner = Window.GetWindow(this) };
        if (dlg.ShowDialog() != true) return;
        if (dlg.SelectedTags.FirstOrDefault() is not int targetIndex) return;
        MoveStepsTo(picks, targetIndex);
    }

    private void MoveStepsTo(IList<ChecklistStep> picks, int targetIndex)
    {
        if (_steps == null || _repo == null) return;
        var picksOrdered = picks
            .Select(s => (step: s, idx: _steps.IndexOf(s)))
            .Where(p => p.idx >= 0)
            .OrderBy(p => p.idx)
            .ToList();
        if (picksOrdered.Count == 0) return;

        var shift = picksOrdered.Count(p => p.idx < targetIndex);
        var adjusted = Math.Clamp(targetIndex - shift, 0, _steps.Count - picksOrdered.Count);
        foreach (var p in picksOrdered.AsEnumerable().Reverse()) _steps.RemoveAt(p.idx);
        for (int k = 0; k < picksOrdered.Count; k++)
            _steps.Insert(adjusted + k, picksOrdered[k].step);

        _repo.MarkDirty();
        RefreshList();
        SelectByReference(picksOrdered.Select(p => p.step));
    }

    private void Delete_Click(object sender, RoutedEventArgs e)
    {
        if (_steps == null || _repo == null) return;
        var picks = StepsList.SelectedItems.Cast<ChecklistStep>().ToList();
        if (picks.Count == 0) return;
        if (MessageBox.Show(Window.GetWindow(this), $"Delete {picks.Count} item{(picks.Count == 1 ? "" : "s")}?",
                "Confirm", MessageBoxButton.YesNo, MessageBoxImage.Question) != MessageBoxResult.Yes) return;
        _repo.LogRemoved(_logKind, $"{picks.Count} removed", _ownerName);
        foreach (var s in picks) _steps.Remove(s);
        _repo.MarkDirty();
        RefreshList();
    }

    // ---- Saved lists (templates) ----
    private void SaveTemplate_Click(object sender, RoutedEventArgs e)
    {
        if (_steps == null || _repo == null) return;
        if (_steps.Count == 0)
        {
            MessageBox.Show(Window.GetWindow(this), "Add some items first, then save the list.",
                "Save list", MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }
        var p = new PromptWindow("Save as reusable list", "Name for this saved list:",
            _ownerName.Length > 0 ? _ownerName : "") { Owner = Window.GetWindow(this) };
        if (p.ShowDialog() != true || string.IsNullOrWhiteSpace(p.Value)) return;
        var tpl = ChecklistTemplateService.CaptureFromSteps(p.Value, _steps);
        _repo.Data.ChecklistTemplates.Add(tpl);
        _repo.LogAdded("Saved list", tpl.Name, $"{tpl.Items.Count} item(s)");
        _repo.Save();
        MessageBox.Show(Window.GetWindow(this), $"Saved '{tpl.Name}' ({tpl.Items.Count} item(s)). You can reuse it from any checklist builder.",
            "Saved list", MessageBoxButton.OK, MessageBoxImage.Information);
    }

    private void LoadTemplate_Click(object sender, RoutedEventArgs e)
    {
        if (_steps == null || _repo == null) return;
        if (_repo.Data.ChecklistTemplates.Count == 0)
        {
            MessageBox.Show(Window.GetWindow(this), "No saved lists yet. Build a list and click 'Save as list...' to create one.",
                "Load a saved list", MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }
        var options = _repo.Data.ChecklistTemplates.Select(t => new PickerItem { Display = t.Display, Tag = t }).ToList();
        var dlg = new ItemPickerWindow("Insert a saved list", options, Array.Empty<object>(), singleSelect: true)
        { Owner = Window.GetWindow(this) };
        if (dlg.ShowDialog() != true) return;
        if (dlg.SelectedTags.FirstOrDefault() is not ChecklistTemplate tpl) return;

        var how = MessageBox.Show(Window.GetWindow(this),
            $"Insert '{tpl.Name}' ({tpl.Items.Count} item(s)).\n\nYes = replace the current items\nNo = append to the end\nCancel = do nothing",
            "Insert a saved list", MessageBoxButton.YesNoCancel, MessageBoxImage.Question);
        if (how == MessageBoxResult.Cancel) return;
        int n = ChecklistTemplateService.ApplyToSteps(tpl, _steps, replace: how == MessageBoxResult.Yes);
        _repo.LogAdded(_logKind, $"{n} added (from saved list '{tpl.Name}')", _ownerName);
        _repo.MarkDirty();
        RefreshList();
    }

    private void ManageTemplates_Click(object sender, RoutedEventArgs e)
    {
        if (_repo == null) return;
        if (_repo.Data.ChecklistTemplates.Count == 0)
        {
            MessageBox.Show(Window.GetWindow(this), "No saved lists yet.",
                "Manage saved lists", MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }
        var options = _repo.Data.ChecklistTemplates.Select(t => new PickerItem { Display = t.Display, Tag = t }).ToList();
        var dlg = new ItemPickerWindow("Manage saved lists — pick one", options, Array.Empty<object>(), singleSelect: true)
        { Owner = Window.GetWindow(this) };
        if (dlg.ShowDialog() != true) return;
        if (dlg.SelectedTags.FirstOrDefault() is not ChecklistTemplate tpl) return;

        var choice = MessageBox.Show(Window.GetWindow(this),
            $"'{tpl.Name}' ({tpl.Items.Count} item(s)).\n\nYes = rename\nNo = delete\nCancel = nothing",
            "Manage saved list", MessageBoxButton.YesNoCancel, MessageBoxImage.Question);
        if (choice == MessageBoxResult.Yes)
        {
            var p = new PromptWindow("Rename saved list", "New name:", tpl.Name) { Owner = Window.GetWindow(this) };
            if (p.ShowDialog() == true && !string.IsNullOrWhiteSpace(p.Value)) { tpl.Name = p.Value.Trim(); _repo.Save(); }
        }
        else if (choice == MessageBoxResult.No)
        {
            if (MessageBox.Show(Window.GetWindow(this), $"Delete saved list '{tpl.Name}'? This does not affect any checklist already built from it.",
                    "Delete saved list", MessageBoxButton.YesNo, MessageBoxImage.Warning) != MessageBoxResult.Yes) return;
            _repo.Data.ChecklistTemplates.Remove(tpl);
            _repo.LogRemoved("Saved list", tpl.Name);
            _repo.Save();
        }
    }

    // ---- helpers ----
    private List<int> SelectedIndicesAscending() =>
        _steps == null ? new List<int>()
        : StepsList.SelectedItems.Cast<ChecklistStep>().Select(s => _steps.IndexOf(s)).Where(i => i >= 0).OrderBy(i => i).ToList();

    private int FirstSelectedIndex() { var l = SelectedIndicesAscending(); return l.Count == 0 ? -1 : l[0]; }
    private int LastSelectedIndex() { var l = SelectedIndicesAscending(); return l.Count == 0 ? -1 : l[^1]; }

    private static string Shorten(string s, int max)
    {
        if (string.IsNullOrEmpty(s)) return "";
        s = s.Replace('\r', ' ').Replace('\n', ' ').Trim();
        return s.Length <= max ? s : s[..(max - 1)] + "…";
    }
}
