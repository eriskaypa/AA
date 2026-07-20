using System;
using System.Collections.Generic;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using AA.Services;

namespace AA.Views;

/// <summary>Shared "Set deadline for selected…" right-click entry, used by every multi-select list of
/// dated items (task subtasks, procedure/crew checklist steps, the Board, the Calendar schedule and the
/// Ctrl+N quick window) so a whole checklist can be dated in one action. Pairs with
/// <see cref="BatchDoneMenu"/>; the mutation and persistence live in <see cref="BatchDeadline"/>.</summary>
internal static class BatchDeadlineMenu
{
    /// <param name="selection">Returns the model objects to date, evaluated fresh on each click.</param>
    public static void Add(ContextMenu cm, AppRepository repo, Func<IEnumerable<object>> selection,
        Action refresh, bool separatorFirst = true)
    {
        if (separatorFirst && cm.Items.Count > 0) cm.Items.Add(new Separator());

        var mi = new MenuItem
        {
            Header = "📅 Set deadline for selected…",
            ToolTip = "Give every selected item the same deadline (or clear it)."
        };
        mi.Click += (_, _) => Apply(cm, repo, selection, refresh);
        cm.Items.Add(mi);
    }

    private static void Apply(ContextMenu cm, AppRepository repo, Func<IEnumerable<object>> selection, Action refresh)
    {
        var items = selection().ToList();
        var owner = cm.PlacementTarget is DependencyObject d ? Window.GetWindow(d) : null;
        if (items.Count == 0)
        {
            MessageBox.Show(owner, "Select one or more items first, then set the deadline.",
                "Set deadline", MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }

        // Pre-fill with the only deadline already shared by the selection (if any), so re-dating is quick.
        var existing = items.Select(CurrentDeadline).Distinct().ToList();
        var dlg = new DatePromptWindow("Set deadline",
            $"Apply one deadline to {items.Count} selected item{(items.Count == 1 ? "" : "s")}:",
            existing.Count == 1 ? existing[0] : null);
        if (owner != null) dlg.Owner = owner;
        if (dlg.ShowDialog() != true) return;

        int n = BatchDeadline.SetDeadlineAll(items, dlg.SelectedDate);
        if (n > 0) { repo.MarkDirty(); repo.FlushIfDirty(); }
        refresh?.Invoke();
    }

    private static DateTime? CurrentDeadline(object? item) => item switch
    {
        AA.Models.TaskItem t => t.Deadline,
        AA.Models.Procedure p => p.Deadline,
        AA.Models.ChecklistStep s => s.Deadline,
        _ => null
    };
}
