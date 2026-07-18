using System.Collections.Generic;
using AA.Models;

namespace AA.Services;

/// <summary>Sets the done/complete state on a heterogeneous selection of completable items — tasks and
/// subtasks (<see cref="TaskItem"/>), procedure/crew checklist steps (<see cref="ChecklistStep"/>) and
/// procedures (<see cref="Procedure"/>) — so every "Mark selected as done" right-click menu shares one
/// definition of what "done" means (and keeps IsComplete/Status/Done in sync via the model setters).</summary>
public static class BatchDone
{
    /// <summary>Apply done/undone to a single model object. Returns true only if this actually CHANGED the
    /// item's state (so pure no-ops don't trigger a save). Un-completing follows the model's own contract —
    /// it demotes only a <em>completed</em> item and preserves an in-progress/blocked workflow status,
    /// exactly as <see cref="TaskItem.IsComplete"/> does — so the three completable kinds behave alike.</summary>
    public static bool SetDone(object? item, bool done)
    {
        switch (item)
        {
            case TaskItem t:
                if (t.IsComplete == done) return false;   // no-op: leaves InProgress/Blocked untouched
                t.IsComplete = done;
                return true;
            case ChecklistStep s:
                if (s.Done == done) return false;
                s.Done = done;
                return true;
            case Procedure p:
                if (done)
                {
                    if (p.Status == WorkStatus.Done) return false;
                    p.Status = WorkStatus.Done;
                    return true;
                }
                if (p.Status != WorkStatus.Done) return false;   // preserve InProgress / Blocked / Todo
                p.Status = WorkStatus.Todo;
                return true;
            default: return false;
        }
    }

    /// <summary>Apply to every item; returns how many were actually changed.</summary>
    public static int SetDoneAll(IEnumerable<object?> items, bool done)
    {
        int n = 0;
        foreach (var i in items) if (SetDone(i, done)) n++;
        return n;
    }
}
