using System;
using System.Collections.Generic;
using System.Linq;
using System.Windows;
using System.Windows.Input;
using AA.Models;
using AA.Services;

namespace AA.Views;

/// <summary>Obsidian-style quick switcher (Ctrl+O): fuzzy-jump to any item by name, kind or #tag.
/// Type to filter, ↑/↓ to move, Enter or double-click to open, Esc to close.</summary>
public partial class QuickSwitcherWindow : Window
{
    private readonly AppRepository _repo;
    private readonly Action<HierarchyItem> _navigate;

    private sealed class Row
    {
        public required HierarchyItem Item { get; init; }
        public string Name => Item.Name;
        public string KindLabel => AppRepository.KindLabel(Item.Kind);
        public string Tags => Item.Tags.Count > 0 ? "#" + string.Join("  #", Item.Tags) : "";
    }

    public QuickSwitcherWindow(AppRepository repo, Action<HierarchyItem> navigate)
    {
        _repo = repo;
        _navigate = navigate;
        InitializeComponent();
        Loaded += (_, _) => { Refresh(); SearchBox.Focus(); };
    }

    private void SearchBox_TextChanged(object sender, System.Windows.Controls.TextChangedEventArgs e) => Refresh();

    private void Refresh()
    {
        // Tags are stored without the leading '#', but the UI shows and advertises the '#tag' form,
        // so accept either — strip a leading '#' the user types.
        var q = (SearchBox.Text ?? "").Trim().TrimStart('#');
        var rows = _repo.AllItems()
            .Select(i => (item: i, score: Score(i, q)))
            .Where(x => q.Length == 0 || x.score > 0)
            .OrderByDescending(x => x.score)
            .ThenBy(x => x.item.Name, StringComparer.OrdinalIgnoreCase)
            .Take(80)
            .Select(x => new Row { Item = x.item })
            .ToList();
        ResultList.ItemsSource = rows;
        if (rows.Count > 0) ResultList.SelectedIndex = 0;
    }

    /// <summary>Simple weighted fuzzy score. Name prefix &gt; name contains &gt; tag &gt; kind.
    /// Also rewards subsequence matches so "eqpump" can find "Equipment Pump".</summary>
    private static int Score(HierarchyItem i, string q)
    {
        if (q.Length == 0) return 1;
        var oic = StringComparison.OrdinalIgnoreCase;
        var name = i.Name ?? "";
        int s = 0;
        if (name.StartsWith(q, oic)) s += 120;
        else if (name.Contains(q, oic)) s += 60;
        else if (IsSubsequence(q, name)) s += 25;

        if (i.Tags.Any(t => t.StartsWith(q, oic))) s += 45;
        else if (i.Tags.Any(t => t.Contains(q, oic))) s += 22;

        if (AppRepository.KindLabel(i.Kind).Contains(q, oic)) s += 8;
        if (!string.IsNullOrEmpty(i.Description) && i.Description.Contains(q, oic)) s += 5;
        return s;
    }

    private static bool IsSubsequence(string needle, string haystack)
    {
        int j = 0;
        for (int k = 0; k < haystack.Length && j < needle.Length; k++)
            if (char.ToLowerInvariant(haystack[k]) == char.ToLowerInvariant(needle[j])) j++;
        return j == needle.Length;
    }

    private void SearchBox_PreviewKeyDown(object sender, KeyEventArgs e)
    {
        switch (e.Key)
        {
            case Key.Down: Move(1); e.Handled = true; break;
            case Key.Up: Move(-1); e.Handled = true; break;
            case Key.Enter: OpenSelected(); e.Handled = true; break;
            case Key.Escape: Close(); e.Handled = true; break;
        }
    }

    private void Move(int delta)
    {
        int n = ResultList.Items.Count;
        if (n == 0) return;
        int i = ResultList.SelectedIndex < 0 ? 0 : ResultList.SelectedIndex + delta;
        ResultList.SelectedIndex = Math.Clamp(i, 0, n - 1);
        if (ResultList.SelectedItem != null) ResultList.ScrollIntoView(ResultList.SelectedItem);
    }

    private void ResultList_MouseDoubleClick(object sender, MouseButtonEventArgs e) => OpenSelected();

    private void OpenSelected()
    {
        if (ResultList.SelectedItem is Row r)
        {
            Close();
            _navigate(r.Item);
        }
    }
}
