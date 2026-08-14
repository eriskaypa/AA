using System;
using System.Collections.Generic;
using System.Linq;
using AA.Models;

namespace AA.Services;

/// <summary>Deleting a whole selection at once, and — just as importantly — describing what that would
/// destroy BEFORE it happens. Sits alongside <see cref="BatchDone"/> and <see cref="BatchDeadline"/> and
/// follows the same shape: pure operations over a selection, no UI, so the destructive part is testable.
///
/// Top-level items (Equipment/Area, Task, Procedure, Vessel) are soft-deleted to the Trash as one undoable
/// batch. Nested things — a subtask inside a task, a procedure step — are removed from their owning
/// collection, because that is what the app's existing single-item delete does and the Trash has no
/// representation for them.</summary>
public static class BatchDelete
{
    /// <summary>What a deletion would actually destroy — the counts worth showing before it happens,
    /// including the ones the user cannot see from the list they are looking at.</summary>
    public sealed class Summary
    {
        public int Equipment, Tasks, Procedures, Vessels;
        /// <summary>Selected items that are locked, and so will be skipped rather than deleted.</summary>
        public int Locked;
        /// <summary>Subtasks/steps/components that ride along inside the selected items.</summary>
        public int Descendants;
        /// <summary>Selected items carrying attached files.</summary>
        public int WithAttachments;
        /// <summary>Selected items that other items link to.</summary>
        public int LinkedFromElsewhere;

        public int Total => Equipment + Tasks + Procedures + Vessels;
        public bool IsEmpty => Total == 0 && Locked == 0;

        /// <summary>"4 tasks, 2 procedures, 1 equipment/area" — only the kinds actually present.</summary>
        public string KindBreakdown()
        {
            var parts = new List<string>();
            if (Tasks > 0) parts.Add($"{Tasks} task{S(Tasks)}");
            if (Procedures > 0) parts.Add($"{Procedures} procedure{S(Procedures)}");
            if (Equipment > 0) parts.Add($"{Equipment} equipment/area{(Equipment == 1 ? "" : "s")}");
            if (Vessels > 0) parts.Add($"{Vessels} vessel{S(Vessels)}");
            return parts.Count == 0 ? "nothing" : string.Join(", ", parts);
        }

        private static string S(int n) => n == 1 ? "" : "s";
    }

    /// <summary>Inspect a selection without touching anything. <paramref name="repo"/> is used only to
    /// count incoming links.</summary>
    public static Summary Describe(AppRepository repo, IEnumerable<object?> selection)
    {
        var s = new Summary();
        foreach (var item in TopLevel(selection))
        {
            if (ItemLockService.IsGated(item)) { s.Locked++; continue; }

            switch (item)
            {
                case Equipment eq:
                    s.Equipment++;
                    s.Descendants += eq.Components.Count;
                    break;
                case TaskItem t:
                    s.Tasks++;
                    s.Descendants += CountSubtasks(t);
                    break;
                case Procedure p:
                    s.Procedures++;
                    s.Descendants += p.Steps.Count;
                    break;
                case Vessel:
                    s.Vessels++;
                    break;
            }

            if (HasAttachments(item)) s.WithAttachments++;
            if (repo != null && repo.ReferencedBy(item).Any()) s.LinkedFromElsewhere++;
        }
        return s;
    }

    /// <summary>Move every selected top-level item to the Trash as one undoable batch, skipping locked
    /// ones. Returns how many were deleted. Does NOT save — the caller decides when to persist.</summary>
    public static int TrashAll(AppRepository repo, IEnumerable<object?> selection)
    {
        if (repo == null) return 0;
        var picks = TopLevel(selection).Where(i => !ItemLockService.IsGated(i)).ToList();
        return picks.Count == 0 ? 0 : repo.TrashHierarchyItems(picks);
    }

    /// <summary>Remove selected children (subtasks, procedure steps, components) from the collection that
    /// owns them. These never reach the Trash — the app has no Trash representation for a nested item, and
    /// its existing single-item delete removes them the same way. Returns how many were removed.</summary>
    public static int RemoveAll<T>(ICollection<T> owner, IEnumerable<object?> selection) where T : class
    {
        if (owner == null) return 0;
        var doomed = selection.OfType<T>().Distinct().ToList();
        int n = 0;
        foreach (var item in doomed)
            if (owner.Remove(item)) n++;
        return n;
    }

    /// <summary>The distinct top-level items in a selection.
    ///
    /// Two things this must get right. Selections arrive as view-model rows in some lists and as models in
    /// others, so unwrap before matching. And a selection can contain both a parent and its own descendant
    /// — deleting the parent already takes the child, so the child is dropped here rather than being
    /// "deleted" a second time from a collection it no longer belongs to.</summary>
    private static List<HierarchyItem> TopLevel(IEnumerable<object?> selection)
    {
        var items = new List<HierarchyItem>();
        var seen = new HashSet<Guid>();
        foreach (var o in selection)
        {
            if (Unwrap(o) is not HierarchyItem h) continue;
            if (seen.Add(h.Id)) items.Add(h);
        }

        // Drop anything already covered by an ancestor in the same selection.
        var covered = new HashSet<Guid>();
        foreach (var item in items)
            if (item is TaskItem t)
                foreach (var descendant in Descendants(t))
                    covered.Add(descendant.Id);

        return items.Where(i => !covered.Contains(i.Id)).ToList();
    }

    /// <summary>Lists bind to plain models in some pages and to wrapper rows in others; take either.</summary>
    private static object? Unwrap(object? o)
    {
        if (o == null) return null;
        if (o is HierarchyItem) return o;
        // Row wrappers expose the model as a property named "Item" (see HierarchyPage.Row).
        var prop = o.GetType().GetProperty("Item");
        return prop?.GetValue(o) ?? o;
    }

    private static int CountSubtasks(TaskItem t) => Descendants(t).Count();

    /// <summary>Every nested subtask, with a cycle guard — a malformed save that made a task its own
    /// ancestor would otherwise hang the confirmation dialog.</summary>
    private static IEnumerable<TaskItem> Descendants(TaskItem root)
    {
        var seen = new HashSet<Guid>();
        var stack = new Stack<TaskItem>();
        foreach (var c in root.Subtasks) stack.Push(c);
        while (stack.Count > 0)
        {
            var t = stack.Pop();
            if (!seen.Add(t.Id)) continue;
            yield return t;
            foreach (var c in t.Subtasks) stack.Push(c);
        }
    }

    private static bool HasAttachments(HierarchyItem item) => item switch
    {
        Equipment eq => eq.Container.Files.Count > 0 || eq.Components.Any(c => c.Container.Files.Count > 0),
        TaskItem t => t.Container.Files.Count > 0 || Descendants(t).Any(s => s.Container.Files.Count > 0),
        Procedure p => p.Container.Files.Count > 0 || p.Steps.Any(s => s.Container.Files.Count > 0),
        Vessel v => v.Container.Files.Count > 0,
        _ => false
    };
}
