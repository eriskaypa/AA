using System;

namespace AA.Services;

/// <summary>Keeps a task's optional working range valid: the range is <c>[start .. deadline]</c> and the
/// deadline is always the LAST date. The editors have two independent date pickers (a start and the
/// existing deadline); after either changes they call <see cref="Coerce"/> to nudge the OTHER field the
/// minimal amount needed to keep <c>start &lt;= deadline</c>, so the user can never build an impossible
/// range and the "last date is the deadline" rule always holds.</summary>
public static class WorkRange
{
    /// <summary>Normalise a (start, deadline) pair to dates with <c>start &lt;= deadline</c>.</summary>
    /// <param name="editedStart">True if the user just changed the START picker (so the DEADLINE gives way);
    /// false if they changed the DEADLINE (so the START gives way).</param>
    public static (DateTime? start, DateTime? deadline) Coerce(DateTime? start, DateTime? deadline, bool editedStart)
    {
        start = start?.Date;
        deadline = deadline?.Date;

        if (start is DateTime s)
        {
            if (deadline is not DateTime d)
            {
                // Picking a start with no deadline yet makes the task due that day (a one-day range).
                deadline = s;
            }
            else if (s > d)
            {
                // start after end is impossible: move the field the user did NOT just touch.
                if (editedStart) deadline = s;   // the last date is always the deadline
                else start = d;                  // clamp the start back onto the (earlier) deadline
            }
        }

        return (start, deadline);
    }
}
