using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Documents;
using System.Windows.Input;
using System.Windows.Media;
using AA.Models;
using AA.Services;

namespace AA.Views;

public partial class SearchWindow : Window
{
    private readonly AppRepository _repo;
    private readonly Action<HierarchyItem> _navigate;
    private CancellationTokenSource? _cts;

    public sealed class Row
    {
        public required string OwnerHeader { get; init; }
        public required string Where { get; init; }
        public required TextBlock HighlightedSnippet { get; init; }
        public required HierarchyItem Owner { get; init; }
    }

    public SearchWindow(AppRepository repo, Action<HierarchyItem> navigateToItem)
    {
        InitializeComponent();
        _repo = repo;
        _navigate = navigateToItem;
        Loaded += (_, _) => QueryBox.Focus();
    }

    private async void Go_Click(object sender, RoutedEventArgs e) => await RunAsync();
    private async void QueryBox_KeyDown(object sender, KeyEventArgs e)
    {
        if (e.Key == Key.Enter) { e.Handled = true; await RunAsync(); }
    }

    private async Task RunAsync()
    {
        var query = QueryBox.Text?.Trim() ?? "";
        if (string.IsNullOrEmpty(query))
        {
            ResultsList.ItemsSource = null;
            StatusText.Text = "";
            return;
        }
        _cts?.Cancel();
        _cts = new CancellationTokenSource();
        var token = _cts.Token;
        StatusText.Text = "Searching…";
        GoBtn.IsEnabled = false;
        try
        {
            // Snapshot which top-level items are locked/gated on the UI thread (the lock service's
            // session state isn't thread-safe), then hand an immutable set to the background scan so
            // locked entries only ever match by Name — never by their protected contents.
            var lockedIds = _repo.Data.Equipment.Cast<HierarchyItem>()
                .Concat(_repo.Data.Tasks).Concat(_repo.Data.Procedures).Concat(_repo.Data.Vessels)
                .Where(ItemLockService.IsGated)
                .Select(i => i.Id)
                .ToHashSet();

            // Run the scan off the UI thread so giant databases don't freeze the window.
            var hits = await Task.Run(() => SearchService.Search(_repo.Data, query, 500, lockedIds), token);
            if (token.IsCancellationRequested) return;
            var rows = hits.Select(h => new Row
            {
                Owner = h.Owner,
                OwnerHeader = $"[{h.Owner.Kind}] {h.Owner.Name}",
                Where = h.Where,
                HighlightedSnippet = BuildHighlighted(h.Snippet, h.MatchStart, h.MatchLength)
            }).ToList();
            ResultsList.ItemsSource = rows;
            StatusText.Text = rows.Count == 0
                ? $"No results for \"{query}\"."
                : $"{rows.Count} result{(rows.Count == 1 ? "" : "s")} for \"{query}\".";
        }
        catch (OperationCanceledException) { }
        finally { GoBtn.IsEnabled = true; }
    }

    private static TextBlock BuildHighlighted(string text, int matchStart, int matchLength)
    {
        var tb = new TextBlock { TextWrapping = TextWrapping.NoWrap, TextTrimming = TextTrimming.CharacterEllipsis };
        if (matchStart < 0 || matchStart > text.Length) matchStart = 0;
        var endMatch = Math.Min(text.Length, matchStart + Math.Max(0, matchLength));
        if (matchStart > 0)
            tb.Inlines.Add(new Run(text.Substring(0, matchStart)));
        if (endMatch > matchStart)
        {
            var hit = new Run(text.Substring(matchStart, endMatch - matchStart))
            {
                Background = new SolidColorBrush(Color.FromRgb(0xFF, 0xE0, 0x66)),
                Foreground = Brushes.Black,
                FontWeight = FontWeights.Bold
            };
            tb.Inlines.Add(hit);
        }
        if (endMatch < text.Length)
            tb.Inlines.Add(new Run(text.Substring(endMatch)));
        return tb;
    }

    private void Results_Activate(object sender, MouseButtonEventArgs e) => ActivateSelection();
    private void Results_Key(object sender, KeyEventArgs e)
    {
        if (e.Key == Key.Enter) { e.Handled = true; ActivateSelection(); }
    }

    private void ActivateSelection()
    {
        if (ResultsList.SelectedItem is not Row r) return;
        _navigate?.Invoke(r.Owner);
    }
}
