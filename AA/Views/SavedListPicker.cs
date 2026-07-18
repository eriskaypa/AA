using System.Collections.Generic;
using System.Linq;
using System.Windows;
using AA.Models;
using AA.Services;

namespace AA.Views;

/// <summary>Shared "add tasks from a saved list" flow used by the Board and Planner tabs. Opens a
/// searchable, multi-select picker over every item in every saved list; each picked item becomes a
/// real, standalone Task (To&nbsp;Do) that then behaves like any other task — schedulable, movable,
/// deletable. Saved lists themselves stay untouched (templates and real tasks remain distinct).</summary>
internal static class SavedListPicker
{
    /// <returns>The tasks created (empty if the user cancelled or there was nothing to pick).</returns>
    public static List<TaskItem> PickAndAddTasks(AppRepository repo, Window? owner)
    {
        var created = new List<TaskItem>();

        var templates = repo.Data.ChecklistTemplates;
        if (templates.Count == 0)
        {
            MessageBox.Show("You have no saved lists yet. Build one in the Saved Lists tab first.",
                "Add from saved list", MessageBoxButton.OK, MessageBoxImage.Information);
            return created;
        }

        var options = new List<PickerItem>();
        foreach (var t in templates)
            foreach (var it in t.Items)
                options.Add(new PickerItem
                {
                    Display = $"{(t.Name.Length > 0 ? t.Name : "(unnamed list)")}  ›  "
                              + $"{(it.Title.Length > 0 ? it.Title : "(untitled)")}"
                              + (it.IsJob ? "   · schedulable" : ""),
                    Tag = it
                });

        if (options.Count == 0)
        {
            MessageBox.Show("Your saved lists don't have any items yet.",
                "Add from saved list", MessageBoxButton.OK, MessageBoxImage.Information);
            return created;
        }

        var dlg = new ItemPickerWindow("Search saved lists — pick items to add as tasks", options);
        if (owner != null) dlg.Owner = owner;
        if (dlg.ShowDialog() != true) return created;

        foreach (var it in dlg.SelectedTags.OfType<ChecklistTemplateItem>())
        {
            var task = ChecklistTemplateService.ItemToTask(it);
            repo.Data.Tasks.Add(task);
            created.Add(task);
        }
        if (created.Count > 0) repo.Save();
        return created;
    }
}
