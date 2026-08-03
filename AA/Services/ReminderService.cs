using System;
using System.Collections.Generic;
using AA.Models;

namespace AA.Services;

/// <summary>Computes what's due for the background reminder / daily digest — overdue, due today, and due
/// within the next 7 days — across tasks, subtasks, procedures and their checklist / crew steps (dated,
/// not-done). Ship work-order notifications are intentionally left in each vessel's Work Orders tab, to
/// match the floating due-dates window.</summary>
public static class ReminderService
{
    public sealed record Summary(int Overdue, int DueToday, int DueWeek)
    {
        /// <summary>Overdue + due today + due within the next 7 days.</summary>
        public int Total => Overdue + DueToday + DueWeek;
        public bool Any => Total > 0;

        /// <summary>Short one-line headline for a tray balloon / status line.</summary>
        public string Headline()
        {
            var parts = new List<string>();
            if (Overdue > 0) parts.Add($"{Overdue} overdue");
            if (DueToday > 0) parts.Add($"{DueToday} due today");
            if (DueWeek > 0) parts.Add($"{DueWeek} due this week");
            return parts.Count == 0 ? "Nothing due." : string.Join("  ·  ", parts);
        }
    }

    public static Summary Compute(AppRepository repo, DateTime today)
    {
        int overdue = 0, dueToday = 0, dueWeek = 0;
        var weekEnd = today.AddDays(7);
        foreach (var d in Deadlines(repo))
        {
            var dd = d.Date;
            if (dd < today) overdue++;
            else if (dd == today) dueToday++;
            else if (dd <= weekEnd) dueWeek++;
        }
        return new Summary(overdue, dueToday, dueWeek);
    }

    private static IEnumerable<DateTime> Deadlines(AppRepository repo)
    {
        foreach (var t in repo.Data.Tasks)
            foreach (var d in TaskDeadlines(t)) yield return d;
        foreach (var p in repo.Data.Procedures)
        {
            if (p.Status != WorkStatus.Done && p.Deadline is DateTime pd) yield return pd;
            foreach (var s in p.Steps)
                if (!s.Done && s.Deadline is DateTime sd) yield return sd;
        }
        foreach (var c in repo.Data.Crew)
            foreach (var s in c.Checklist)
                if (!s.Done && s.Deadline is DateTime sd) yield return sd;
    }

    private static IEnumerable<DateTime> TaskDeadlines(TaskItem t)
    {
        if (!t.IsComplete && t.Deadline is DateTime d) yield return d;
        foreach (var st in t.Subtasks)
            foreach (var x in TaskDeadlines(st)) yield return x;
    }
}
