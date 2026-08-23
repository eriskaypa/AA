using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Linq;
using AA.Models;

namespace AA.Services;

/// <summary>The order saved lists appear in — on the Saved Lists tab and, because of that, in a group
/// export. There is no sort field: the order of <see cref="AppData.ChecklistTemplates"/> itself IS the
/// user's arrangement, and System.Text.Json round-trips array order, so it persists for free.
///
/// Lives here rather than in the page so the destructive part — re-anchoring items in a collection — can
/// be tested. Every operation is a permutation: no list is created, removed or duplicated.</summary>
public static class SavedListOrder
{
    /// <summary>Indices, within <paramref name="all"/>, of every list in one group, in current order.
    /// Reordering works on this subsequence: moving by flat index would let a list hop a group boundary
    /// and appear to change group while its GroupId says otherwise.</summary>
    public static List<int> GroupSpan(IList<ChecklistTemplate> all, Guid? groupId)
    {
        var span = new List<int>();
        for (int i = 0; i < all.Count; i++)
            if (all[i].GroupId == groupId) span.Add(i);
        return span;
    }

    /// <summary>Move the picked lists one step up or down within their group. Returns false when they are
    /// already at that end, when the group holds fewer than two lists, or when the picks span groups.</summary>
    public static bool Nudge(ObservableCollection<ChecklistTemplate> all, IReadOnlyList<ChecklistTemplate> picks, bool up)
    {
        if (!SameGroup(picks, out var gid)) return false;
        var span = GroupSpan(all, gid);
        if (span.Count < 2) return false;

        var at = picks.Select(t => span.IndexOf(all.IndexOf(t))).Where(x => x >= 0).OrderBy(x => x).ToList();
        if (at.Count == 0) return false;
        if (up && at[0] == 0) return false;
        if (!up && at[^1] == span.Count - 1) return false;

        // Going down, move the last one first — otherwise earlier moves shuffle the ones behind them.
        foreach (var pos in up ? at : Enumerable.Reverse(at).ToList())
            all.Move(span[pos], span[up ? pos - 1 : pos + 1]);
        return true;
    }

    /// <summary>Move the picked lists to a position within their group (0 = top, span.Count = bottom),
    /// keeping their relative order.</summary>
    public static bool MoveTo(ObservableCollection<ChecklistTemplate> all, IReadOnlyList<ChecklistTemplate> picks, int targetInGroup)
    {
        if (!SameGroup(picks, out var gid)) return false;
        var span = GroupSpan(all, gid);
        if (span.Count < 2) return false;

        var moving = picks.ToHashSet();
        var ordered = span.Select(i => all[i]).ToList();
        if (!moving.All(ordered.Contains)) return false;

        // Rebuild the group's sequence, then re-anchor each slot. Splicing a list out shifts everything
        // after it, so the target is adjusted by however many movers sat before it.
        int before = ordered.Take(Math.Clamp(targetInGroup, 0, ordered.Count)).Count(moving.Contains);
        var remaining = ordered.Where(t => !moving.Contains(t)).ToList();
        var inOrder = ordered.Where(moving.Contains).ToList();   // keep the movers' relative order
        remaining.InsertRange(Math.Clamp(targetInGroup - before, 0, remaining.Count), inOrder);

        for (int pos = 0; pos < span.Count; pos++)
        {
            int from = all.IndexOf(remaining[pos]);
            if (from != span[pos]) all.Move(from, span[pos]);
        }
        return true;
    }

    /// <summary>The entries for a one-group export, in the user's arranged order.</summary>
    public static List<(string? Group, ChecklistTemplate Template)> GroupEntries(AppData data, Guid? groupId)
    {
        var name = groupId is Guid gid
            ? data.ListGroups.FirstOrDefault(g => g.Id == gid)?.Name
            : null;
        return data.ChecklistTemplates.Where(t => t.GroupId == groupId)
                   .Select(t => (string.IsNullOrEmpty(name) ? null : name, t)).ToList();
    }

    /// <summary>The entries for an everything export. Group is the primary key so each group's lists stay
    /// CONTIGUOUS — the PDF emits a heading only when the group changes between consecutive entries, so
    /// interleaved entries would print the same heading twice with the lists split under it. Within a
    /// group, position in the collection preserves the arrangement (OrderBy is stable).</summary>
    public static List<(string? Group, ChecklistTemplate Template)> AllEntries(AppData data)
    {
        string NameFor(Guid? g) =>
            g is Guid gid ? data.ListGroups.FirstOrDefault(x => x.Id == gid)?.Name ?? "" : "";

        var order = new Dictionary<ChecklistTemplate, int>();
        for (int i = 0; i < data.ChecklistTemplates.Count; i++) order[data.ChecklistTemplates[i]] = i;

        return data.ChecklistTemplates
            .OrderBy(t => t.GroupId == null ? "￿" : NameFor(t.GroupId).ToLowerInvariant())
            .ThenBy(t => order[t])
            .Select(t => ((string?)(t.GroupId is Guid gid ? NameFor(gid) : null), t))
            .ToList();
    }

    private static bool SameGroup(IReadOnlyList<ChecklistTemplate> picks, out Guid? groupId)
    {
        groupId = null;
        if (picks == null || picks.Count == 0) return false;
        groupId = picks[0].GroupId;
        var gid = groupId;
        return picks.All(t => t.GroupId == gid);
    }
}
