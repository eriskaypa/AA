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

/// <summary>The "Saved Lists" tab: reusable saved checklists, freely organised into List Groups, with
/// per-list / per-group / all-lists PDF export. Saved lists and groups persist with the rest of the data
/// (and ride along in shared/exported saves).</summary>
public partial class SavedListsPage : UserControl
{
    private AppRepository? _repo;

    public SavedListsPage() { InitializeComponent(); }

    public void Init(AppRepository repo) { _repo = repo; Refresh(); }

    private sealed class ListRow
    {
        public required ChecklistTemplate Tpl { get; init; }
        public string Name => Tpl.Name.Length > 0 ? Tpl.Name : "(unnamed)";
        public int Count => Tpl.Items.Count;
        public required string GroupName { get; init; }
        public required string GroupSort { get; init; }
        /// <summary>Position in Data.ChecklistTemplates. That collection's order IS the user's arranged
        /// order — System.Text.Json round-trips array order, so no separate sort field is needed.</summary>
        public required int SortIdx { get; init; }
    }

    private sealed class ItemRow
    {
        public required string Title { get; init; }
        public required string Meta { get; init; }
        /// <summary>The saved-list item behind this row, so it can be opened read-only on double-click.</summary>
        public required ChecklistTemplateItem Item { get; init; }
    }

    private ChecklistTemplate? Selected => (ListsBox.SelectedItem as ListRow)?.Tpl;

    public void Refresh()
    {
        if (_repo == null) return;
        var keepId = Selected?.Id;

        string GroupNameFor(ChecklistTemplate t)
        {
            if (t.GroupId is Guid gid)
            {
                var g = _repo!.Data.ListGroups.FirstOrDefault(x => x.Id == gid);
                if (g != null) return g.Name.Length > 0 ? g.Name : "(unnamed group)";
            }
            return "Ungrouped";
        }

        var rows = _repo.Data.ChecklistTemplates.Select((t, i) => new ListRow
        {
            Tpl = t,
            GroupName = GroupNameFor(t),
            // Ungrouped sinks to the bottom; named groups sort alphabetically.
            GroupSort = t.GroupId == null ? "￿" : GroupNameFor(t).ToLowerInvariant(),
            SortIdx = i
        }).ToList();

        bool az = SortAz;
        if (SortAzBtn != null) SortAzBtn.IsChecked = az;
        if (UpBtn != null) { UpBtn.IsEnabled = !az; DownBtn.IsEnabled = !az; MoveToBtn.IsEnabled = !az; }

        var view = new ListCollectionView(rows);
        view.SortDescriptions.Add(new SortDescription(nameof(ListRow.GroupSort), ListSortDirection.Ascending));
        // Arranged order by default; alphabetical only while the user asks for it. Either way the
        // underlying collection keeps the arrangement, so turning A-Z off restores it untouched.
        view.SortDescriptions.Add(az
            ? new SortDescription(nameof(ListRow.Name), ListSortDirection.Ascending)
            : new SortDescription(nameof(ListRow.SortIdx), ListSortDirection.Ascending));
        view.GroupDescriptions.Add(new PropertyGroupDescription(nameof(ListRow.GroupName)));
        ListsBox.ItemsSource = view;

        if (keepId is Guid id)
        {
            var keep = rows.FirstOrDefault(r => r.Tpl.Id == id);
            if (keep != null) ListsBox.SelectedItem = keep;
        }

        int lists = _repo.Data.ChecklistTemplates.Count;
        int groups = _repo.Data.ListGroups.Count;
        StatusText.Text = lists == 0
            ? "No saved lists yet. Build a checklist anywhere and click 'Save as list...', or click '+ List'."
            : $"{lists} saved list(s)  ·  {groups} group(s)";

        UpdateDetail();
    }

    private void ListsBox_SelectionChanged(object sender, SelectionChangedEventArgs e) => UpdateDetail();

    private void UpdateDetail()
    {
        var t = Selected;
        DetailRoot.IsEnabled = t != null;
        if (t == null)
        {
            DetailName.Text = "Select a saved list";
            DetailSub.Text = "";
            ItemsPreview.ItemsSource = null;
            return;
        }
        DetailName.Text = t.Name.Length > 0 ? t.Name : "(unnamed)";
        var grp = t.GroupId is Guid gid ? _repo?.Data.ListGroups.FirstOrDefault(g => g.Id == gid)?.Name : null;
        DetailSub.Text = $"{t.Items.Count} item(s)"
            + (string.IsNullOrWhiteSpace(grp) ? "  ·  ungrouped" : $"  ·  group: {grp}")
            + $"  ·  created {t.CreatedUtc.ToLocalTime():yyyy-MM-dd}";
        ItemsPreview.ItemsSource = t.Items.Select(it =>
        {
            var meta = new List<string>();
            if (it.IsJob) meta.Add("job");
            bool hasNotes = !string.IsNullOrWhiteSpace(it.Container?.RichTextXaml);
            int files = it.Container?.Files.Count ?? 0;
            if (hasNotes) meta.Add("notes");
            if (files > 0) meta.Add($"{files} file{(files == 1 ? "" : "s")}");
            return new ItemRow { Title = it.Title.Length > 0 ? it.Title : "(untitled)", Meta = string.Join("  ·  ", meta), Item = it };
        }).ToList();
    }

    /// <summary>Double-clicking an item opens its notes + files READ-ONLY, so links can be followed without
    /// exporting a PDF first — and without any risk of editing the reusable saved list.</summary>
    private void ItemsPreview_DoubleClick(object sender, System.Windows.Input.MouseButtonEventArgs e)
    {
        if (ItemsPreview.SelectedItem is not ItemRow row) return;
        var listName = Selected?.Name;
        new ContainerViewerWindow(
            row.Title,
            row.Item.Container,
            $"Saved-list item{(string.IsNullOrWhiteSpace(listName) ? "" : $" · {listName}")} — read-only. Click a link to open it; double-click a file to open it.")
        { Owner = Window.GetWindow(this) }.ShowDialog();
    }

    // ---- Groups ----
    private void NewGroup_Click(object sender, RoutedEventArgs e)
    {
        if (_repo == null) return;
        var p = new PromptWindow("New List Group", "Group name:") { Owner = Window.GetWindow(this) };
        if (p.ShowDialog() != true || string.IsNullOrWhiteSpace(p.Value)) return;
        _repo.Data.ListGroups.Add(new ListGroup { Name = p.Value.Trim() });
        _repo.Save();
        Refresh();
    }

    private void ManageGroups_Click(object sender, RoutedEventArgs e)
    {
        if (_repo == null) return;
        if (_repo.Data.ListGroups.Count == 0)
        {
            MessageBox.Show(Window.GetWindow(this), "No groups yet. Click '+ Group' to create one.",
                "Manage groups", MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }
        var options = _repo.Data.ListGroups.Select(g => new PickerItem
        { Display = $"{g.Name}  ·  {_repo.Data.ChecklistTemplates.Count(t => t.GroupId == g.Id)} list(s)", Tag = g }).ToList();
        var dlg = new ItemPickerWindow("Manage groups — pick one", options, Array.Empty<object>(), singleSelect: true)
        { Owner = Window.GetWindow(this) };
        if (dlg.ShowDialog() != true || dlg.SelectedTags.FirstOrDefault() is not ListGroup grp) return;

        var choice = MessageBox.Show(Window.GetWindow(this),
            $"'{grp.Name}'.\n\nYes = rename\nNo = delete (its lists become ungrouped)\nCancel = nothing",
            "Manage group", MessageBoxButton.YesNoCancel, MessageBoxImage.Question);
        if (choice == MessageBoxResult.Yes)
        {
            var p = new PromptWindow("Rename group", "New name:", grp.Name) { Owner = Window.GetWindow(this) };
            if (p.ShowDialog() == true && !string.IsNullOrWhiteSpace(p.Value)) { grp.Name = p.Value.Trim(); _repo.Save(); Refresh(); }
        }
        else if (choice == MessageBoxResult.No)
        {
            if (MessageBox.Show(Window.GetWindow(this), $"Delete group '{grp.Name}'? Its saved lists are kept (they become ungrouped).",
                    "Delete group", MessageBoxButton.YesNo, MessageBoxImage.Warning) != MessageBoxResult.Yes) return;
            foreach (var t in _repo.Data.ChecklistTemplates.Where(t => t.GroupId == grp.Id)) t.GroupId = null;
            _repo.Data.ListGroups.Remove(grp);
            _repo.Save();
            Refresh();
        }
    }

    private void AssignGroup_Click(object sender, RoutedEventArgs e)
    {
        if (_repo == null || Selected is not ChecklistTemplate t) { NeedSelection(); return; }
        var options = new List<PickerItem> { new() { Display = "(No group — ungrouped)", Tag = "none" } };
        options.AddRange(_repo.Data.ListGroups.Select(g => new PickerItem { Display = g.Name, Tag = g }));
        var dlg = new ItemPickerWindow($"Move '{t.Name}' to group", options, Array.Empty<object>(), singleSelect: true)
        { Owner = Window.GetWindow(this) };
        if (dlg.ShowDialog() != true) return;
        var pick = dlg.SelectedTags.FirstOrDefault();
        t.GroupId = pick is ListGroup g ? g.Id : null;
        _repo.Save();
        Refresh();
    }

    // ---- Lists ----
    private void NewList_Click(object sender, RoutedEventArgs e)
    {
        if (_repo == null) return;
        var p = new PromptWindow("New saved list", "Name:") { Owner = Window.GetWindow(this) };
        if (p.ShowDialog() != true || string.IsNullOrWhiteSpace(p.Value)) return;
        var tpl = new ChecklistTemplate { Name = p.Value.Trim() };
        _repo.Data.ChecklistTemplates.Add(tpl);
        _repo.LogAdded("Saved list", tpl.Name, "empty");
        _repo.Save();
        Refresh();
        SelectTemplate(tpl.Id);
    }

    private void Rename_Click(object sender, RoutedEventArgs e)
    {
        if (_repo == null || Selected is not ChecklistTemplate t) { NeedSelection(); return; }
        var p = new PromptWindow("Rename saved list", "New name:", t.Name) { Owner = Window.GetWindow(this) };
        if (p.ShowDialog() == true && !string.IsNullOrWhiteSpace(p.Value)) { t.Name = p.Value.Trim(); _repo.Save(); Refresh(); }
    }

    private void Delete_Click(object sender, RoutedEventArgs e)
    {
        if (_repo == null || Selected is not ChecklistTemplate t) { NeedSelection(); return; }
        if (MessageBox.Show(Window.GetWindow(this), $"Delete saved list '{t.Name}'? This does not affect any checklist already built from it.",
                "Delete saved list", MessageBoxButton.YesNo, MessageBoxImage.Warning) != MessageBoxResult.Yes) return;
        _repo.Data.ChecklistTemplates.Remove(t);
        _repo.LogRemoved("Saved list", t.Name);
        _repo.Save();
        Refresh();
    }

    private void Duplicate_Click(object sender, RoutedEventArgs e)
    {
        if (_repo == null || Selected is not ChecklistTemplate t) { NeedSelection(); return; }
        var copy = ChecklistTemplateService.Clone(t, t.Name + " (copy)");
        _repo.Data.ChecklistTemplates.Add(copy);
        _repo.LogAdded("Saved list", copy.Name, $"{copy.Items.Count} item(s)");
        _repo.Save();
        Refresh();
        SelectTemplate(copy.Id);
    }

    private void EditItems_Click(object sender, RoutedEventArgs e)
    {
        if (_repo == null || Selected is not ChecklistTemplate t) { NeedSelection(); return; }
        new TemplateEditorWindow(t, _repo) { Owner = Window.GetWindow(this) }.ShowDialog();
        Refresh();
    }

    // ---- PDF export ----
    // ---- Arranging the order lists appear in (and therefore export in) ----

    private const string SortAzKey = "savedlists";

    /// <summary>Whether the tab is showing alphabetically instead of the user's arranged order.</summary>
    private bool SortAz =>
        _repo != null && _repo.Data.Ui.SortAZ.TryGetValue(SortAzKey, out var on) && on;

    private void SortAz_Click(object sender, RoutedEventArgs e)
    {
        if (_repo == null) return;
        _repo.Data.Ui.SortAZ[SortAzKey] = SortAzBtn.IsChecked == true;
        _repo.Save();
        Refresh();
        StatusText.Text = SortAz
            ? "Showing A-Z. Your arranged order is kept, and is what exports use — switch this off to see it."
            : "Showing your arranged order. This is the order lists appear in when you export a group.";
    }

    /// <summary>The selected templates, in the order they currently sit in the collection.</summary>
    private List<ChecklistTemplate> SelectedTemplates()
    {
        if (_repo == null) return new List<ChecklistTemplate>();
        var picked = ListsBox.SelectedItems.Cast<object>()
            .Select(o => (o as ListRow)?.Tpl)
            .Where(t => t != null)
            .Cast<ChecklistTemplate>()
            .ToHashSet();
        return _repo.Data.ChecklistTemplates.Where(picked.Contains).ToList();
    }

    /// <summary>Indices, within Data.ChecklistTemplates, of every list sharing a group with the given one.
    /// Reordering works on this subsequence: moving on flat indices would let a list hop a group boundary
    /// and appear to change group while its GroupId says otherwise.</summary>
    private List<int> GroupSpan(Guid? groupId)
    {
        var span = new List<int>();
        for (int i = 0; i < _repo!.Data.ChecklistTemplates.Count; i++)
            if (_repo.Data.ChecklistTemplates[i].GroupId == groupId) span.Add(i);
        return span;
    }

    /// <summary>Shared guard: a reorder needs a repo, manual ordering, and a selection inside one group.</summary>
    private bool CanReorder(out List<ChecklistTemplate> picks, out List<int> span)
    {
        picks = new List<ChecklistTemplate>();
        span = new List<int>();
        if (_repo == null) return false;
        if (SortAz)
        {
            MessageBox.Show(Window.GetWindow(this),
                "Turn off \"Sort A-Z\" first — while it is on you are seeing alphabetical order, not your own.",
                "Arrange lists", MessageBoxButton.OK, MessageBoxImage.Information);
            return false;
        }
        picks = SelectedTemplates();
        if (picks.Count == 0) { NeedSelection(); return false; }

        var gid = picks[0].GroupId;
        if (picks.Any(t => t.GroupId != gid))
        {
            MessageBox.Show(Window.GetWindow(this),
                "Those lists are in different groups. Lists are arranged within their own group, so select lists from one group at a time.",
                "Arrange lists", MessageBoxButton.OK, MessageBoxImage.Information);
            return false;
        }
        span = GroupSpan(gid);
        return span.Count > 1;   // nothing to arrange in a group of one
    }

    private void Up_Click(object sender, RoutedEventArgs e) => Nudge(up: true);
    private void Down_Click(object sender, RoutedEventArgs e) => Nudge(up: false);

    private void Nudge(bool up)
    {
        if (!CanReorder(out var picks, out _)) return;
        if (!SavedListOrder.Nudge(_repo!.Data.ChecklistTemplates, picks, up)) return;   // already at that end
        CommitOrder(picks);
    }

    private void MoveTo_Click(object sender, RoutedEventArgs e)
    {
        if (!CanReorder(out var picks, out var span)) return;
        var coll = _repo!.Data.ChecklistTemplates;
        var moving = picks.ToHashSet();

        var options = new List<PickerItem> { new() { Display = "(Move to top of group)", Tag = (object)0 } };
        for (int pos = 0; pos < span.Count; pos++)
        {
            var t = coll[span[pos]];
            if (moving.Contains(t)) continue;   // "before myself" is meaningless
            options.Add(new PickerItem { Display = $"Before: {Shorten(t.Name, 60)}", Tag = (object)pos });
        }
        options.Add(new PickerItem { Display = "(Move to bottom of group)", Tag = (object)span.Count });

        var dlg = new ItemPickerWindow(
            $"Move {picks.Count} list{(picks.Count == 1 ? "" : "s")} to...",
            options, Array.Empty<object>(), singleSelect: true)
        { Owner = Window.GetWindow(this) };
        if (dlg.ShowDialog() != true) return;
        if (dlg.SelectedTags.FirstOrDefault() is not int target) return;

        if (!SavedListOrder.MoveTo(coll, picks, target)) return;
        CommitOrder(picks);
    }

    /// <summary>Persist a new order and keep the moved lists selected, so a second nudge acts on the same
    /// rows rather than whatever happens to sit there now.</summary>
    private void CommitOrder(IReadOnlyList<ChecklistTemplate> picks)
    {
        _repo!.Save();
        var keep = picks.Select(t => t.Id).ToList();
        Refresh();
        Reselect(keep);
        StatusText.Text = "Order saved — this is the order the group exports in.";
    }

    private void Reselect(IReadOnlyList<Guid> ids)
    {
        ListsBox.SelectedItems.Clear();
        if (ListsBox.ItemsSource is not System.Collections.IEnumerable src) return;
        var want = ids.ToHashSet();
        object? first = null;
        foreach (var o in src)
            if (o is ListRow r && want.Contains(r.Tpl.Id)) { ListsBox.SelectedItems.Add(o); first ??= o; }
        if (first != null) ListsBox.ScrollIntoView(first);
    }

    private static string Shorten(string? s, int max)
    {
        s = (s ?? "").Trim();
        if (s.Length == 0) return "(unnamed)";
        return s.Length <= max ? s : s[..(max - 1)] + "…";
    }

    private void ExportList_Click(object sender, RoutedEventArgs e)
    {
        if (_repo == null || Selected is not ChecklistTemplate t) { NeedSelection(); return; }
        ExportToPdf(t.Name.Length > 0 ? t.Name : "Saved list", new[] { ((string?)null, t) });
    }

    private void ExportGroup_Click(object sender, RoutedEventArgs e)
    {
        if (_repo == null || Selected is not ChecklistTemplate t) { NeedSelection(); return; }
        List<(string?, ChecklistTemplate)> entries;
        string title;
        if (t.GroupId is Guid gid && _repo.Data.ListGroups.FirstOrDefault(g => g.Id == gid) is ListGroup grp)
        {
            title = grp.Name;
            entries = SavedListOrder.GroupEntries(_repo.Data, gid)
                .Select(x => (x.Group, x.Template)).ToList();
        }
        else
        {
            title = "Ungrouped lists";
            entries = SavedListOrder.GroupEntries(_repo.Data, null)
                .Select(x => (x.Group, x.Template)).ToList();
        }
        ExportToPdf(title, entries);
    }

    private void ExportAll_Click(object sender, RoutedEventArgs e)
    {
        if (_repo == null) return;
        if (_repo.Data.ChecklistTemplates.Count == 0) { MessageBox.Show(Window.GetWindow(this), "No saved lists to export.", "Export", MessageBoxButton.OK, MessageBoxImage.Information); return; }

        var entries = SavedListOrder.AllEntries(_repo.Data)
            .Select(x => ((string?)x.Group, x.Template)).ToList();
        ExportToPdf("All saved lists", entries);
    }

    private void ExportToPdf(string title, IReadOnlyList<(string?, ChecklistTemplate)> entries)
    {
        if (entries.Count == 0) { MessageBox.Show(Window.GetWindow(this), "Nothing to export.", "Export", MessageBoxButton.OK, MessageBoxImage.Information); return; }

        // Always ask, and never remember: numbering says the items run in sequence, which is true of a
        // procedure and false of a set of checks that can be done in any order. Bullets are preselected
        // because they claim less.
        int listCount = entries.Count;
        var numbered = ListStylePromptWindow.Ask(Window.GetWindow(this),
            listCount == 1
                ? "How should the items in this list be shown in the PDF?"
                : $"How should the items in these {listCount} lists be shown in the PDF?");
        if (numbered == null) return;   // cancelled

        var dlg = new SaveFileDialog
        {
            Title = "Export saved lists to PDF",
            Filter = "PDF document (*.pdf)|*.pdf",
            DefaultExt = ".pdf",
            FileName = Sanitize(title) + ".pdf"
        };
        if (dlg.ShowDialog() != true) return;
        try
        {
            PdfExporter.ExportSavedLists(title, entries, dlg.FileName, numbered.Value);
            if (MessageBox.Show(Window.GetWindow(this), $"Exported to:\n{dlg.FileName}\n\nOpen it now?",
                    "Export complete", MessageBoxButton.YesNo, MessageBoxImage.Information) == MessageBoxResult.Yes)
                System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(dlg.FileName) { UseShellExecute = true });
        }
        catch (Exception ex)
        {
            MessageBox.Show(Window.GetWindow(this), $"Could not export the PDF:\n\n{ex.Message}", "Export failed", MessageBoxButton.OK, MessageBoxImage.Error);
        }
    }

    // ---- helpers ----
    private void SelectTemplate(Guid id)
    {
        if (ListsBox.ItemsSource is ListCollectionView v)
            foreach (ListRow r in v.OfType<ListRow>())
                if (r.Tpl.Id == id) { ListsBox.SelectedItem = r; ListsBox.ScrollIntoView(r); return; }
    }

    private void NeedSelection() =>
        MessageBox.Show(Window.GetWindow(this), "Select a saved list first.", "Saved Lists", MessageBoxButton.OK, MessageBoxImage.Information);

    private static string Sanitize(string s)
    {
        foreach (var c in System.IO.Path.GetInvalidFileNameChars()) s = s.Replace(c, '_');
        return string.IsNullOrWhiteSpace(s) ? "saved-lists" : s.Trim();
    }
}
