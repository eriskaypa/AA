using System;
using System.Collections.Generic;
using System.Linq;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using AA.Services;

namespace AA.Views;

/// <summary>Shared builder for the "Mark selected as done / not done" right-click menu entries used by
/// every multi-select list of completable items (Board, subtasks, checklist steps, Calendar schedule,
/// the Ctrl+N quick window). Each caller supplies a snapshot-at-click-time selection accessor and a
/// refresh callback; the mutation and persistence are centralised here.</summary>
internal static class BatchDoneMenu
{
    /// <summary>Append the two batch-done items (optionally preceded by a separator) to a context menu.</summary>
    /// <param name="selection">Returns the model objects to act on, evaluated fresh on each click.</param>
    public static void Add(ContextMenu cm, AppRepository repo, Func<IEnumerable<object>> selection,
        Action refresh, bool separatorFirst = true)
    {
        if (separatorFirst && cm.Items.Count > 0) cm.Items.Add(new Separator());

        var done = new MenuItem { Header = "✓ Mark selected as done" };
        done.Click += (_, _) => Apply(repo, selection, true, refresh);
        var notDone = new MenuItem { Header = "○ Mark selected as not done" };
        notDone.Click += (_, _) => Apply(repo, selection, false, refresh);
        cm.Items.Add(done);
        cm.Items.Add(notDone);
    }

    /// <summary>Right-click selection semantics for a multi-select list: if the clicked row is already
    /// part of the selection, leave the whole selection intact (so the menu acts on all of it); otherwise
    /// select just the clicked row. Call from PreviewMouseRightButtonDown. (ListViewItem : ListBoxItem.)</summary>
    public static void RightClickSelect(Selector list, System.Windows.DependencyObject? source)
    {
        var container = UiTree.FindAncestor<ListBoxItem>(source);
        if (container == null) return;
        if (!container.IsSelected)
        {
            if (list is ListBox lb) lb.SelectedItems.Clear();
            else if (list is ListView lv) lv.SelectedItems.Clear();
            container.IsSelected = true;
        }
    }

    private static void Apply(AppRepository repo, Func<IEnumerable<object>> selection, bool done, Action refresh)
    {
        int n = BatchDone.SetDoneAll(selection().ToList(), done);
        if (n > 0) { repo.MarkDirty(); repo.FlushIfDirty(); }
        refresh?.Invoke();
    }
}
