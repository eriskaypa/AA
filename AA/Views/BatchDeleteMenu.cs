using System;
using System.Collections.Generic;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using AA.Services;

namespace AA.Views;

/// <summary>Shared builder for the "Delete selected" right-click entry on multi-select lists of
/// Equipment/Areas, Tasks and Procedures. Companion to <see cref="BatchDoneMenu"/> and
/// <see cref="BatchDeadlineMenu"/>, with the same call shape.
///
/// The confirmation is the point of this class. Deleting several items at once hides consequences that
/// are obvious one at a time: a collapsed task takes its subtasks with it, an item may be linked from
/// somewhere the user is not looking, and a locked item will be skipped rather than deleted. All of that
/// is counted and shown before anything is destroyed.</summary>
internal static class BatchDeleteMenu
{
    /// <summary>Append the batch-delete entry (optionally preceded by a separator) to a context menu.</summary>
    /// <param name="selection">Returns the model objects to act on, evaluated fresh on each click.</param>
    /// <param name="refresh">Called after a successful delete so the list can redraw.</param>
    public static void Add(ContextMenu cm, AppRepository repo, Func<IEnumerable<object>> selection,
        Action refresh, bool separatorFirst = true)
    {
        if (separatorFirst && cm.Items.Count > 0) cm.Items.Add(new Separator());

        var del = new MenuItem
        {
            Header = "🗑 Delete selected...",
            ToolTip = "Move every selected item to the Trash. Restore from File ▸ Trash, or undo with Ctrl+Z."
        };
        del.Click += (s, _) => Run(cm, repo, selection, refresh);
        cm.Items.Add(del);
    }

    /// <summary>Confirm, then delete. Returns how many were trashed (0 when cancelled or nothing eligible),
    /// so a page's own toolbar Delete button can share this exact path.</summary>
    public static int Run(DependencyObject? ownerSource, AppRepository repo,
        Func<IEnumerable<object>> selection, Action? refresh)
    {
        if (repo == null) return 0;
        var owner = OwnerWindow(ownerSource);
        var picks = selection().ToList();

        var sum = BatchDelete.Describe(repo, picks);
        if (sum.IsEmpty)
        {
            MessageBox.Show(owner, "Select one or more items first.", "Delete selected",
                MessageBoxButton.OK, MessageBoxImage.Information);
            return 0;
        }
        if (sum.Total == 0)
        {
            // Everything picked was locked — deleting nothing silently would look like a broken menu.
            MessageBox.Show(owner,
                sum.Locked == 1
                    ? "That item is locked. Unlock it before deleting it."
                    : $"All {sum.Locked} selected items are locked. Unlock them before deleting.",
                "Nothing deleted", MessageBoxButton.OK, MessageBoxImage.Information);
            return 0;
        }

        if (MessageBox.Show(owner, BuildPrompt(repo, sum), "Confirm delete",
                MessageBoxButton.YesNo, MessageBoxImage.Warning, MessageBoxResult.No) != MessageBoxResult.Yes)
            return 0;

        int n = BatchDelete.TrashAll(repo, picks);
        if (n > 0) repo.Save();
        refresh?.Invoke();
        return n;
    }

    /// <summary>Spell out the consequences that a multi-select hides.</summary>
    private static string BuildPrompt(AppRepository repo, BatchDelete.Summary sum)
    {
        var lines = new List<string>
        {
            sum.Total == 1 ? "Move 1 item to the Trash?" : $"Move {sum.Total} items to the Trash?",
            "",
            "    " + sum.KindBreakdown()
        };

        if (sum.Descendants > 0)
            lines.Add($"    {sum.Descendants} subtask/step/component{(sum.Descendants == 1 ? "" : "s")} inside them will be deleted too.");
        if (sum.WithAttachments > 0)
            lines.Add($"    {sum.WithAttachments} of them ha{(sum.WithAttachments == 1 ? "s" : "ve")} attached files (the files stay on disk).");
        if (sum.LinkedFromElsewhere > 0)
            lines.Add($"    {sum.LinkedFromElsewhere} {(sum.LinkedFromElsewhere == 1 ? "is" : "are")} linked from other items; those links show \"(missing)\" until the Trash is emptied.");
        if (sum.Locked > 0)
            lines.Add($"    {sum.Locked} locked item{(sum.Locked == 1 ? " is" : "s are")} selected and will be skipped.");

        // The Trash is capped, so a big enough batch silently pushes the oldest entries out of undo range.
        int after = repo.Data.Trash.Count + sum.Total;
        if (after > AppRepository.MaxTrashItems)
            lines.Add($"    Note: the Trash holds {AppRepository.MaxTrashItems} items, so the {after - AppRepository.MaxTrashItems} oldest will be permanently removed.");

        lines.Add("");
        lines.Add("You can restore them from File ▸ Trash, or undo with Ctrl+Z.");
        return string.Join("\n", lines);
    }

    private static Window? OwnerWindow(DependencyObject? source)
    {
        if (source is ContextMenu cm)
            return Window.GetWindow(cm.PlacementTarget) ?? Application.Current?.MainWindow;
        if (source != null)
            return Window.GetWindow(source) ?? Application.Current?.MainWindow;
        return Application.Current?.MainWindow;
    }
}
