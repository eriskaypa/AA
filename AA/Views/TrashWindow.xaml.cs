using System;
using System.Collections.Generic;
using System.Linq;
using System.Windows;
using AA.Models;
using AA.Services;

namespace AA.Views;

/// <summary>Browser for soft-deleted items: restore them (back to their original tab) or remove them for
/// good. Restores raise <see cref="Restored"/> so the host can refresh the affected pages.</summary>
public partial class TrashWindow : Window
{
    private readonly AppRepository _repo;

    /// <summary>Raised with the restored item's type ("Equipment"/"Task"/"Procedure"/"Vessel"/"Crew")
    /// so the host can refresh the right page.</summary>
    public event Action<string>? Restored;

    public TrashWindow(AppRepository repo)
    {
        InitializeComponent();
        _repo = repo;
        List.ItemsSource = _repo.Data.Trash;
    }

    private void Restore_Click(object sender, RoutedEventArgs e)
    {
        var picks = List.SelectedItems.OfType<TrashedItem>().ToList();
        if (picks.Count == 0) return;
        var restored = new HashSet<string>();
        foreach (var ti in picks)
        {
            var type = _repo.RestoreTrash(ti);
            if (type != null) restored.Add(type);
        }
        if (restored.Count == 0)
        {
            MessageBox.Show(this, "Couldn't restore the selected item(s).", "Restore",
                MessageBoxButton.OK, MessageBoxImage.Warning);
            return;
        }
        _repo.Save();
        foreach (var type in restored) Restored?.Invoke(type);
    }

    private void DeletePermanent_Click(object sender, RoutedEventArgs e)
    {
        var picks = List.SelectedItems.OfType<TrashedItem>().ToList();
        if (picks.Count == 0) return;
        if (MessageBox.Show(this, $"Permanently delete {picks.Count} item(s) from the Trash? This cannot be undone.",
                "Delete permanently", MessageBoxButton.YesNo, MessageBoxImage.Warning) != MessageBoxResult.Yes) return;
        foreach (var ti in picks) _repo.PurgeTrash(ti);
        _repo.Save();
    }

    private void Empty_Click(object sender, RoutedEventArgs e)
    {
        if (_repo.Data.Trash.Count == 0) return;
        if (MessageBox.Show(this, $"Permanently remove all {_repo.Data.Trash.Count} item(s) in the Trash? This cannot be undone.",
                "Empty Trash", MessageBoxButton.YesNo, MessageBoxImage.Warning) != MessageBoxResult.Yes) return;
        _repo.EmptyTrash();
        _repo.Save();
    }

    private void Close_Click(object sender, RoutedEventArgs e) => Close();
}
