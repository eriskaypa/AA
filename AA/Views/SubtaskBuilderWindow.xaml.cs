using System;
using System.Collections.Generic;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using AA.Models;
using AA.Services;

namespace AA.Views;

/// <summary>Comprehensive subtask builder for a Task — bulk-create, reorder, insert, move, edit and
/// delete subtasks. Mirrors the procedure Checklist builder, but each subtask is a full TaskItem
/// (with its own deadline / recurrence / status / notes, editable via the subtask editor).</summary>
public partial class SubtaskBuilderWindow : Window
{
    private readonly TaskItem _task;
    private readonly AppRepository _repo;

    public SubtaskBuilderWindow(TaskItem task, AppRepository repo)
    {
        InitializeComponent();
        _task = task;
        _repo = repo;
        HeaderText.Text = $"Subtask builder — {task.Name}";
        RefreshList();
        Closing += (_, _) => _repo.FlushIfDirty();
    }

    // ---- Saved lists (reusable checklist templates) ----
    private void SaveTemplate_Click(object sender, RoutedEventArgs e)
    {
        if (_task.Subtasks.Count == 0)
        {
            MessageBox.Show(this, "Add some subtasks first, then save the list.",
                "Save list", MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }
        var p = new PromptWindow("Save as reusable list", "Name for this saved list:", _task.Name) { Owner = this };
        if (p.ShowDialog() != true || string.IsNullOrWhiteSpace(p.Value)) return;
        var tpl = ChecklistTemplateService.CaptureFromSubtasks(p.Value, _task.Subtasks);
        _repo.Data.ChecklistTemplates.Add(tpl);
        _repo.LogAdded("Saved list", tpl.Name, $"{tpl.Items.Count} item(s)");
        _repo.Save();
        MessageBox.Show(this, $"Saved '{tpl.Name}' ({tpl.Items.Count} item(s)). You can reuse it from any checklist builder.",
            "Saved list", MessageBoxButton.OK, MessageBoxImage.Information);
    }

    private void LoadTemplate_Click(object sender, RoutedEventArgs e)
    {
        if (_repo.Data.ChecklistTemplates.Count == 0)
        {
            MessageBox.Show(this, "No saved lists yet. Build a list and click 'Save as list...' to create one.",
                "Load a saved list", MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }
        var options = _repo.Data.ChecklistTemplates.Select(t => new PickerItem { Display = t.Display, Tag = t }).ToList();
        var dlg = new ItemPickerWindow("Insert a saved list", options, Array.Empty<object>(), singleSelect: true) { Owner = this };
        if (dlg.ShowDialog() != true) return;
        if (dlg.SelectedTags.FirstOrDefault() is not ChecklistTemplate tpl) return;

        var how = MessageBox.Show(this,
            $"Insert '{tpl.Name}' ({tpl.Items.Count} item(s)).\n\nYes = replace the current subtasks\nNo = append to the end\nCancel = do nothing",
            "Insert a saved list", MessageBoxButton.YesNoCancel, MessageBoxImage.Question);
        if (how == MessageBoxResult.Cancel) return;
        int n = ChecklistTemplateService.ApplyToSubtasks(tpl, _task.Subtasks, replace: how == MessageBoxResult.Yes);
        _repo.LogAdded("Subtask", $"{n} added (from saved list '{tpl.Name}')", _task.Name);
        _repo.MarkDirty();
        RefreshList();
    }

    private void RefreshList()
    {
        var keepIds = ItemsList.SelectedItems.Cast<TaskItem>().Select(s => s.Id).ToHashSet();
        ItemsList.ItemsSource = null;
        ItemsList.ItemsSource = _task.Subtasks;
        if (keepIds.Count > 0)
        {
            ItemsList.SelectedItems.Clear();
            foreach (var s in _task.Subtasks)
                if (keepIds.Contains(s.Id)) ItemsList.SelectedItems.Add(s);
        }
    }

    private void SelectByReference(IEnumerable<TaskItem> items)
    {
        ItemsList.SelectedItems.Clear();
        TaskItem? first = null;
        foreach (var s in items)
        {
            ItemsList.SelectedItems.Add(s);
            first ??= s;
        }
        if (first != null) ItemsList.ScrollIntoView(first);
    }

    private void AddAll_Click(object sender, RoutedEventArgs e)
    {
        var lines = (BulkBox.Text ?? "")
            .Replace("\r\n", "\n").Split('\n')
            .Select(l => l.Trim()).Where(l => l.Length > 0).ToList();
        if (lines.Count == 0) return;
        if (ReplaceBox.IsChecked == true) _task.Subtasks.Clear();
        foreach (var line in lines) _task.Subtasks.Add(new TaskItem { Name = line });
        BulkBox.Clear();
        _repo.LogAdded("Subtask", $"{lines.Count} added (bulk)", _task.Name);
        _repo.MarkDirty();
        RefreshList();
    }

    private void ClearText_Click(object sender, RoutedEventArgs e) => BulkBox.Clear();

    private void AddOne_Click(object sender, RoutedEventArgs e) => AddAt(_task.Subtasks.Count);

    private void InsertBefore_Click(object sender, RoutedEventArgs e)
    {
        var idx = FirstSelectedIndex();
        if (idx < 0) { AddAt(0); return; }
        AddAt(idx);
    }

    private void InsertAfter_Click(object sender, RoutedEventArgs e)
    {
        var idx = LastSelectedIndex();
        if (idx < 0) { AddAt(_task.Subtasks.Count); return; }
        AddAt(idx + 1);
    }

    private void AddAt(int index)
    {
        var p = new PromptWindow("New subtask", "Name:") { Owner = this };
        if (p.ShowDialog() != true || string.IsNullOrWhiteSpace(p.Value)) return;
        index = Math.Clamp(index, 0, _task.Subtasks.Count);
        var sub = new TaskItem { Name = p.Value };
        _task.Subtasks.Insert(index, sub);
        _repo.LogAdded("Subtask", sub.Name, _task.Name);
        _repo.MarkDirty();
        RefreshList();
        SelectByReference(new[] { sub });
    }

    private void EditOne_Click(object sender, RoutedEventArgs e) => EditSelected();
    private void ItemsList_DoubleClick(object sender, MouseButtonEventArgs e) => EditSelected();

    private void EditSelected()
    {
        if (ItemsList.SelectedItem is not TaskItem st) return;
        var w = new SubtaskEditorWindow(st, _repo) { Owner = this };
        w.ShowDialog();
        _repo.FlushIfDirty();
        RefreshList();
    }

    private void Up_Click(object sender, RoutedEventArgs e)
    {
        var picks = SelectedIndicesAscending();
        if (picks.Count == 0 || picks[0] == 0) return;
        foreach (var i in picks) _task.Subtasks.Move(i, i - 1);
        _repo.MarkDirty();
        RefreshList();
    }

    private void Down_Click(object sender, RoutedEventArgs e)
    {
        var picks = SelectedIndicesAscending();
        if (picks.Count == 0 || picks[^1] == _task.Subtasks.Count - 1) return;
        foreach (var i in picks.AsEnumerable().Reverse()) _task.Subtasks.Move(i, i + 1);
        _repo.MarkDirty();
        RefreshList();
    }

    private void MoveTo_Click(object sender, RoutedEventArgs e)
    {
        var picks = ItemsList.SelectedItems.Cast<TaskItem>().ToList();
        if (picks.Count == 0) return;

        var selectedSet = picks.ToHashSet();
        var options = new List<PickerItem> { new() { Display = "(Move to top)", Tag = (object)0 } };
        for (int i = 0; i < _task.Subtasks.Count; i++)
        {
            var s = _task.Subtasks[i];
            if (selectedSet.Contains(s)) continue;
            options.Add(new PickerItem { Display = $"Before: {Shorten(s.Name, 60)}", Tag = (object)i });
        }
        options.Add(new PickerItem { Display = "(Move to bottom)", Tag = (object)_task.Subtasks.Count });

        var dlg = new ItemPickerWindow(
            $"Move {picks.Count} subtask{(picks.Count == 1 ? "" : "s")} to...",
            options, Array.Empty<object>(), singleSelect: true)
        { Owner = this };
        if (dlg.ShowDialog() != true) return;
        if (dlg.SelectedTags.FirstOrDefault() is not int targetIndex) return;

        MoveItemsTo(picks, targetIndex);
    }

    private void MoveItemsTo(IList<TaskItem> picks, int targetIndex)
    {
        var picksOrdered = picks
            .Select(s => (item: s, idx: _task.Subtasks.IndexOf(s)))
            .Where(p => p.idx >= 0)
            .OrderBy(p => p.idx)
            .ToList();
        if (picksOrdered.Count == 0) return;

        var shift = picksOrdered.Count(p => p.idx < targetIndex);
        var adjusted = Math.Clamp(targetIndex - shift, 0, _task.Subtasks.Count - picksOrdered.Count);

        foreach (var p in picksOrdered.AsEnumerable().Reverse()) _task.Subtasks.RemoveAt(p.idx);
        for (int k = 0; k < picksOrdered.Count; k++)
            _task.Subtasks.Insert(adjusted + k, picksOrdered[k].item);

        _repo.MarkDirty();
        RefreshList();
        SelectByReference(picksOrdered.Select(p => p.item));
    }

    private void Delete_Click(object sender, RoutedEventArgs e)
    {
        var picks = ItemsList.SelectedItems.Cast<TaskItem>().ToList();
        if (picks.Count == 0) return;
        if (MessageBox.Show($"Delete {picks.Count} subtask{(picks.Count == 1 ? "" : "s")}?",
                "Confirm", MessageBoxButton.YesNo, MessageBoxImage.Question) != MessageBoxResult.Yes) return;
        _repo.LogRemoved("Subtask", $"{picks.Count} removed", _task.Name);
        foreach (var s in picks) _task.Subtasks.Remove(s);
        _repo.MarkDirty();
        RefreshList();
    }

    private void Close_Click(object sender, RoutedEventArgs e) => Close();

    // ---- helpers ----
    private List<int> SelectedIndicesAscending() =>
        ItemsList.SelectedItems.Cast<TaskItem>()
            .Select(s => _task.Subtasks.IndexOf(s))
            .Where(i => i >= 0)
            .OrderBy(i => i)
            .ToList();

    private int FirstSelectedIndex()
    {
        var list = SelectedIndicesAscending();
        return list.Count == 0 ? -1 : list[0];
    }

    private int LastSelectedIndex()
    {
        var list = SelectedIndicesAscending();
        return list.Count == 0 ? -1 : list[^1];
    }

    private static string Shorten(string s, int max)
    {
        if (string.IsNullOrEmpty(s)) return "";
        s = s.Replace('\r', ' ').Replace('\n', ' ').Trim();
        return s.Length <= max ? s : s[..(max - 1)] + "…";
    }
}
