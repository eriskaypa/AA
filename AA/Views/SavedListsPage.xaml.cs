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

        var rows = _repo.Data.ChecklistTemplates.Select(t => new ListRow
        {
            Tpl = t,
            GroupName = GroupNameFor(t),
            // Ungrouped sinks to the bottom; named groups sort alphabetically.
            GroupSort = t.GroupId == null ? "￿" : GroupNameFor(t).ToLowerInvariant()
        }).ToList();

        var view = new ListCollectionView(rows);
        view.SortDescriptions.Add(new SortDescription(nameof(ListRow.GroupSort), ListSortDirection.Ascending));
        view.SortDescriptions.Add(new SortDescription(nameof(ListRow.Name), ListSortDirection.Ascending));
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
            entries = _repo.Data.ChecklistTemplates.Where(x => x.GroupId == gid)
                .OrderBy(x => x.Name, StringComparer.OrdinalIgnoreCase)
                .Select(x => ((string?)grp.Name, x)).ToList();
        }
        else
        {
            title = "Ungrouped lists";
            entries = _repo.Data.ChecklistTemplates.Where(x => x.GroupId == null)
                .OrderBy(x => x.Name, StringComparer.OrdinalIgnoreCase)
                .Select(x => ((string?)null, x)).ToList();
        }
        ExportToPdf(title, entries);
    }

    private void ExportAll_Click(object sender, RoutedEventArgs e)
    {
        if (_repo == null) return;
        if (_repo.Data.ChecklistTemplates.Count == 0) { MessageBox.Show(Window.GetWindow(this), "No saved lists to export.", "Export", MessageBoxButton.OK, MessageBoxImage.Information); return; }

        string NameFor(Guid? g) => g is Guid gid ? _repo!.Data.ListGroups.FirstOrDefault(x => x.Id == gid)?.Name ?? "" : "";
        var entries = _repo.Data.ChecklistTemplates
            .OrderBy(t => t.GroupId == null ? "￿" : NameFor(t.GroupId).ToLowerInvariant())
            .ThenBy(t => t.Name, StringComparer.OrdinalIgnoreCase)
            .Select(t => ((string?)(t.GroupId is Guid gid ? NameFor(gid) : null), t))
            .ToList();
        ExportToPdf("All saved lists", entries);
    }

    private void ExportToPdf(string title, IReadOnlyList<(string?, ChecklistTemplate)> entries)
    {
        if (entries.Count == 0) { MessageBox.Show(Window.GetWindow(this), "Nothing to export.", "Export", MessageBoxButton.OK, MessageBoxImage.Information); return; }
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
            PdfExporter.ExportSavedLists(title, entries, dlg.FileName);
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
