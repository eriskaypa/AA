using System;
using System.Collections.Generic;
using AA.Models;

namespace AA.Services;

/// <summary>Sets one shared deadline across a selection of dated items — tasks and subtasks
/// (<see cref="TaskItem"/>), procedures, and procedure/crew checklist steps — so a whole checklist can be
/// dated in one go. Mirrors <see cref="BatchDone"/>: it reports only real changes, so a no-op selection
/// doesn't trigger a save.</summary>
public static class BatchDeadline
{
    /// <summary>Apply <paramref name="date"/> (null clears) to one item. Returns true if it actually changed.
    /// A task's working range is kept valid: clearing the deadline also clears the range start (a range
    /// can't exist without its end), and a start later than the new deadline is clamped back onto it.</summary>
    public static bool SetDeadline(object? item, DateTime? date)
    {
        var d = date?.Date;
        switch (item)
        {
            case TaskItem t:
                if (d is null)
                {
                    if (t.Deadline is null && t.RangeStart is null) return false;
                    t.Deadline = null;
                    t.RangeStart = null;
                    return true;
                }
                var (ns, nd) = WorkRange.Coerce(t.RangeStart, d, editedStart: false);
                if (t.Deadline == nd && t.RangeStart == ns) return false;
                t.RangeStart = ns;
                t.Deadline = nd;
                return true;

            case Procedure p:
                if (p.Deadline == d) return false;
                p.Deadline = d;
                return true;

            case ChecklistStep s:
                if (s.Deadline == d) return false;
                s.Deadline = d;
                return true;

            default: return false;
        }
    }

    /// <summary>Apply to every item; returns how many were actually changed.</summary>
    public static int SetDeadlineAll(IEnumerable<object?> items, DateTime? date)
    {
        int n = 0;
        foreach (var i in items) if (SetDeadline(i, date)) n++;
        return n;
    }
}
