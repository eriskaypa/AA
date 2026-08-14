using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Data;
using AA.Models;
using AA.Services;

namespace AA.Views;

/// <summary>Picks a saved list and how it should read, then hands back the finished lines. Deliberately
/// shows a preview: the user is inserting into a note they care about, and should see what lands there
/// before it does.</summary>
public partial class InsertSavedListWindow : Window
{
    private readonly AppRepository _repo;
    private readonly List<ChecklistTemplate> _all;

    /// <summary>The lines to insert, in order. Empty if the dialog was cancelled.</summary>
    public List<string> Lines { get; private set; } = new();

    /// <summary>True for a numbered list, false for bullets.</summary>
    public bool Numbered { get; private set; }

    /// <summary>The chosen list's name, for the status line.</summary>
    public string ListName { get; private set; } = "";

    public InsertSavedListWindow(AppRepository repo)
    {
        InitializeComponent();
        _repo = repo;
        _all = repo.Data.ChecklistTemplates.OrderBy(t => t.Name, StringComparer.CurrentCultureIgnoreCase).ToList();

        if (_all.Count == 0)
        {
            // Nothing to insert: say why, rather than showing an empty box the user has to interpret.
            FootNote.Text = "You have no saved lists yet. Build one in the Saved Lists tab first.";
            OkBtn.IsEnabled = false;
            SearchBox.IsEnabled = false;
            return;
        }

        Bind(_all);
        if (ListsBox.Items.Count > 0) ListsBox.SelectedIndex = 0;
    }

    private void Bind(IEnumerable<ChecklistTemplate> items)
    {
        // Group by List Group so the picker reads the same way the Saved Lists tab does.
        var groups = _repo.Data.ListGroups.ToDictionary(g => g.Id, g => g.Name);
        var rows = items.Select(t => new Row
        {
            Template = t,
            Display = t.Display,
            GroupName = t.GroupId is Guid gid && groups.TryGetValue(gid, out var n) ? n : "Ungrouped"
        }).ToList();

        var view = new ListCollectionView(rows);
        view.GroupDescriptions.Add(new PropertyGroupDescription(nameof(Row.GroupName)));
        ListsBox.ItemsSource = view;
    }

    private sealed class Row
    {
        public ChecklistTemplate Template { get; init; } = new();
        public string Display { get; init; } = "";
        public string GroupName { get; init; } = "";
    }

    private ChecklistTemplate? Selected => (ListsBox.SelectedItem as Row)?.Template;

    private void Search_Changed(object sender, TextChangedEventArgs e)
    {
        var q = SearchBox.Text?.Trim() ?? "";
        Bind(q.Length == 0
            ? _all
            : _all.Where(t => t.Name.Contains(q, StringComparison.CurrentCultureIgnoreCase)
                           || t.Items.Any(i => i.Title.Contains(q, StringComparison.CurrentCultureIgnoreCase))));
        if (ListsBox.Items.Count > 0) ListsBox.SelectedIndex = 0;
        UpdatePreview();
    }

    private void Lists_SelectionChanged(object sender, SelectionChangedEventArgs e) => UpdatePreview();
    private void Option_Changed(object sender, RoutedEventArgs e) => UpdatePreview();

    private void UpdatePreview()
    {
        if (PreviewText == null) return;
        var t = Selected;
        if (t == null) { PreviewText.Text = ""; FootNote.Text = ""; OkBtn.IsEnabled = false; return; }

        var lines = BuildLines(t);
        OkBtn.IsEnabled = lines.Count > 0;

        bool numbered = NumbersRadio.IsChecked == true;
        PreviewText.Text = lines.Count == 0
            ? "(this saved list has no items)"
            : string.Join("\n", lines.Select((l, i) => (numbered ? $"{i + 1}. " : "• ") + l));

        // Be honest about what is NOT carried across, rather than letting the user discover it later.
        int withNotes = t.Items.Count(i => !string.IsNullOrWhiteSpace(i.Container.RichTextXaml));
        int withFiles = t.Items.Sum(i => i.Container.Files.Count);
        var notes = new List<string>();
        if (withNotes > 0) notes.Add($"{withNotes} item{(withNotes == 1 ? " has" : "s have")} notes");
        if (withFiles > 0) notes.Add($"{withFiles} attached file{(withFiles == 1 ? "" : "s")}");
        FootNote.Text = notes.Count == 0
            ? $"{lines.Count} line{(lines.Count == 1 ? "" : "s")} will be inserted."
            : $"{lines.Count} line{(lines.Count == 1 ? "" : "s")} will be inserted. Not carried over: {string.Join(", ", notes)}.";
    }

    private List<string> BuildLines(ChecklistTemplate t)
    {
        bool withDuration = DurationCheck.IsChecked == true;
        return t.Items
            .Select(i => i.Title?.Trim() ?? "")
            .Where(s => s.Length > 0)
            .Select((s, idx) =>
            {
                if (!withDuration) return s;
                var mins = t.Items.Where(i => (i.Title?.Trim() ?? "").Length > 0).ElementAt(idx).DurationMinutes;
                return mins > 0 ? $"{s}  ({mins} min)" : s;
            })
            .ToList();
    }

    private void Ok_Click(object sender, RoutedEventArgs e)
    {
        var t = Selected;
        if (t == null) return;
        Lines = BuildLines(t);
        if (Lines.Count == 0) return;
        Numbered = NumbersRadio.IsChecked == true;
        ListName = t.Name;
        DialogResult = true;
    }
}
