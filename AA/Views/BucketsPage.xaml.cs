using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Data;
using System.Windows.Input;
using AA.Models;
using AA.Services;

namespace AA.Views;

/// <summary>The Buckets tab: predefine buckets (a location, a rank, …) that tasks &amp; procedures are
/// sorted into (up to two each) from the Ctrl+N quick-work window. Left = bucket definitions grouped by
/// category; right = the items in the selected bucket.</summary>
public partial class BucketsPage : UserControl
{
    private AppRepository? _repo;

    /// <summary>Set by the host so double-clicking a member can jump to it.</summary>
    public Action<HierarchyItem>? Navigate { get; set; }

    public BucketsPage() { InitializeComponent(); }

    public void Init(AppRepository repo) { _repo = repo; Refresh(); }

    private sealed class BucketRow
    {
        public required QuickBucket Bucket { get; init; }
        public string Name => Bucket.Name.Length > 0 ? Bucket.Name : "(unnamed)";
        public int Count { get; init; }
        public required string Category { get; init; }
        public required string CategorySort { get; init; }
    }

    private sealed class MemberRow
    {
        public required IBucketable Item { get; init; }
        public required string Kind { get; init; }
        public required string Name { get; init; }
        public string? Parent { get; init; }
        public string Display => Parent == null ? $"[{Kind}]  {Name}" : $"[{Kind}]  {Name}   —   in {Parent}";
    }

    private QuickBucket? Selected => (BucketList.SelectedItem as BucketRow)?.Bucket;

    /// <summary>Every bucketable item — tasks (+ nested subtasks, recursively), procedures (+ their
    /// checklist steps) — each with a kind label and parent name for context.</summary>
    private IEnumerable<MemberRow> AllBucketableRows()
    {
        if (_repo == null) yield break;
        foreach (var t in _repo.Data.Tasks)
            foreach (var r in TaskRows(t, null)) yield return r;
        foreach (var p in _repo.Data.Procedures)
        {
            yield return new MemberRow { Item = p, Kind = "Procedure", Name = NameOr(p.Name) };
            foreach (var s in p.Steps)
                yield return new MemberRow { Item = s, Kind = "Checklist step", Name = NameOr(s.Title), Parent = p.Name };
        }
    }

    private static IEnumerable<MemberRow> TaskRows(TaskItem t, string? parent)
    {
        yield return new MemberRow { Item = t, Kind = parent == null ? "Task" : "Subtask", Name = NameOr(t.Name), Parent = parent };
        foreach (var st in t.Subtasks)
            foreach (var r in TaskRows(st, t.Name)) yield return r;
    }

    private static string NameOr(string s) => s.Length > 0 ? s : "(unnamed)";

    public void Refresh()
    {
        if (_repo == null) return;
        var keepId = Selected?.Id;

        // Materialise the full bucketable set once, then count per bucket.
        var allRows = AllBucketableRows().ToList();
        var rows = _repo.Data.QuickBuckets.Select(b => new BucketRow
        {
            Bucket = b,
            Count = allRows.Count(r => r.Item.BucketIds.Contains(b.Id)),
            Category = b.Category.Length > 0 ? b.Category : "(Uncategorised)",
            CategorySort = b.Category.Length > 0 ? b.Category.ToLowerInvariant() : "￿"
        }).ToList();

        var view = new ListCollectionView(rows);
        view.SortDescriptions.Add(new SortDescription(nameof(BucketRow.CategorySort), ListSortDirection.Ascending));
        view.SortDescriptions.Add(new SortDescription(nameof(BucketRow.Name), ListSortDirection.Ascending));
        view.GroupDescriptions.Add(new PropertyGroupDescription(nameof(BucketRow.Category)));
        BucketList.ItemsSource = view;

        if (keepId is Guid id)
        {
            var keep = rows.FirstOrDefault(r => r.Bucket.Id == id);
            if (keep != null) BucketList.SelectedItem = keep;
        }

        StatusText.Text = _repo.Data.QuickBuckets.Count == 0
            ? "No buckets yet. Click “+ New bucket” to define one (e.g. name “Engine room”, category “Location”)."
            : $"{_repo.Data.QuickBuckets.Count} bucket(s).";
        ShowMembers();
    }

    private void BucketList_SelectionChanged(object sender, SelectionChangedEventArgs e) => ShowMembers();

    private void ShowMembers()
    {
        var b = Selected;
        if (_repo == null || b == null)
        {
            MembersHeader.Text = "Select a bucket to see the tasks & procedures in it.";
            MemberList.ItemsSource = null;
            return;
        }
        var members = AllBucketableRows().Where(r => r.Item.BucketIds.Contains(b.Id))
            .OrderBy(r => r.Kind, StringComparer.OrdinalIgnoreCase).ThenBy(r => r.Name, StringComparer.OrdinalIgnoreCase)
            .ToList();
        MembersHeader.Text = $"🪣 {(b.Name.Length > 0 ? b.Name : "(unnamed)")}"
            + (b.Category.Length > 0 ? $"  ·  {b.Category}" : "") + $"   —   {members.Count} item(s)";
        MemberList.ItemsSource = members;
    }

    // ---- Bucket definition management ----
    private void New_Click(object sender, RoutedEventArgs e)
    {
        if (_repo == null) return;
        var p = new PromptWindow("New bucket", "Bucket name (e.g. a location or a rank):") { Owner = Window.GetWindow(this) };
        if (p.ShowDialog() != true || string.IsNullOrWhiteSpace(p.Value)) return;
        var c = new PromptWindow("Category (optional)", "What does it represent? (e.g. Location, Rank) — leave blank for none:", "") { Owner = Window.GetWindow(this) };
        var category = c.ShowDialog() == true ? (c.Value?.Trim() ?? "") : "";
        var bucket = new QuickBucket { Name = p.Value.Trim(), Category = category };
        _repo.Data.QuickBuckets.Add(bucket);
        _repo.LogAdded("Bucket", bucket.Name, category);
        _repo.Save();
        Refresh();
        SelectBucket(bucket.Id);
    }

    private void Rename_Click(object sender, RoutedEventArgs e)
    {
        if (_repo == null || Selected is not QuickBucket b) { Need(); return; }
        var p = new PromptWindow("Rename bucket", "New name:", b.Name) { Owner = Window.GetWindow(this) };
        if (p.ShowDialog() == true && !string.IsNullOrWhiteSpace(p.Value)) { b.Name = p.Value.Trim(); _repo.Save(); Refresh(); }
    }

    private void SetCategory_Click(object sender, RoutedEventArgs e)
    {
        if (_repo == null || Selected is not QuickBucket b) { Need(); return; }
        var p = new PromptWindow("Set category", "Category (e.g. Location, Rank) — blank clears it:", b.Category) { Owner = Window.GetWindow(this) };
        if (p.ShowDialog() == true) { b.Category = p.Value?.Trim() ?? ""; _repo.Save(); Refresh(); }
    }

    private void Delete_Click(object sender, RoutedEventArgs e)
    {
        if (_repo == null || Selected is not QuickBucket b) { Need(); return; }
        var members = AllBucketableRows().Where(r => r.Item.BucketIds.Contains(b.Id)).ToList();
        if (MessageBox.Show(Window.GetWindow(this),
                $"Delete bucket '{b.Name}'? {(members.Count > 0 ? $"Its {members.Count} item(s) will be removed from it (the items themselves are kept)." : "")}",
                "Delete bucket", MessageBoxButton.YesNo, MessageBoxImage.Warning) != MessageBoxResult.Yes) return;
        foreach (var r in members) r.Item.BucketIds.Remove(b.Id);
        _repo.Data.QuickBuckets.Remove(b);
        _repo.LogRemoved("Bucket", b.Name);
        _repo.Save();
        Refresh();
    }

    // ---- Members ----
    private void Member_DoubleClick(object sender, MouseButtonEventArgs e) => OpenMember_Click(sender, e);

    /// <summary>Select the right-clicked member so the context menu (Open / Remove) acts on it — WPF
    /// doesn't select a row on right-click by default.</summary>
    private void Member_RightButtonSelect(object sender, MouseButtonEventArgs e)
    {
        if (ItemsControl.ContainerFromElement(MemberList, e.OriginalSource as DependencyObject) is ListBoxItem item)
            item.IsSelected = true;
    }

    private void OpenMember_Click(object sender, RoutedEventArgs e)
    {
        if (_repo == null || MemberList.SelectedItem is not MemberRow r) return;
        var owner = Window.GetWindow(this);
        if (r.Kind is "Task" or "Procedure")
        {
            if (r.Item is HierarchyItem hi) Navigate?.Invoke(hi);   // top-level: jump to it in its tab
        }
        else if (r.Item is TaskItem st)                              // subtask: open its editor
        {
            new SubtaskEditorWindow(st, _repo) { Owner = owner }.ShowDialog();
            _repo.FlushIfDirty(); Refresh();
        }
        else if (r.Item is ChecklistStep step)                       // checklist step: open its editor
        {
            new ChecklistStepEditorWindow(step, _repo) { Owner = owner }.ShowDialog();
            _repo.FlushIfDirty(); Refresh();
        }
    }

    private void RemoveMember_Click(object sender, RoutedEventArgs e)
    {
        if (_repo == null || Selected is not QuickBucket b || MemberList.SelectedItem is not MemberRow r) return;
        r.Item.BucketIds.Remove(b.Id);
        _repo.Save();
        Refresh();
    }

    private void SelectBucket(Guid id)
    {
        if (BucketList.ItemsSource is ListCollectionView v)
            foreach (BucketRow r in v.OfType<BucketRow>())
                if (r.Bucket.Id == id) { BucketList.SelectedItem = r; BucketList.ScrollIntoView(r); return; }
    }

    private void Need() =>
        MessageBox.Show(Window.GetWindow(this), "Select a bucket first.", "Buckets", MessageBoxButton.OK, MessageBoxImage.Information);
}
