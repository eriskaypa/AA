using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using System.Xml;
using AA.Models;

namespace AA.Services;

/// <summary>Comprehensive in-memory full-text search across every text-bearing field
/// in <see cref="AppData"/>. Designed to stay responsive for tens of thousands of items:
/// container rich-text is stripped to plain text on the fly via an XmlReader scan, and
/// each match yields a small snippet around the hit so the UI never has to load a
/// FlowDocument for items that aren't opened.</summary>
public static class SearchService
{
    public enum HitKind { Item, Component, Subtask, Step, File }

    public sealed class Hit
    {
        public required HierarchyItem Owner;     // top-level item the hit lives under (always navigable)
        public required HitKind Kind;
        public required string Where;            // human label like "Name", "Notes", "Component › Notes"
        public required string Snippet;          // text excerpt with the match in-place
        public required int MatchStart;          // offset of match inside Snippet
        public required int MatchLength;
        public Guid? ChildId;                    // component / subtask / step id when applicable
    }

    /// <param name="lockedOwnerIds">Ids of top-level items that are password-locked and not
    /// unlocked this session. Such items expose only their <c>Name</c> to search; their
    /// description, notes, files and child content (components / subtasks / steps) are omitted
    /// so the lock isn't bypassed via search snippets. Null = nothing is locked.</param>
    public static IReadOnlyList<Hit> Search(AppData data, string query, int maxResults = 500,
        ISet<Guid>? lockedOwnerIds = null)
    {
        var hits = new List<Hit>();
        if (string.IsNullOrWhiteSpace(query) || data == null) return hits;
        var q = query.Trim();
        var cmp = StringComparison.OrdinalIgnoreCase;

        void Add(HierarchyItem owner, HitKind kind, string where, string text, Guid? childId = null)
        {
            if (hits.Count >= maxResults) return;
            if (string.IsNullOrEmpty(text)) return;
            var idx = text.IndexOf(q, cmp);
            if (idx < 0) return;
            var (snippet, start) = MakeSnippet(text, idx, q.Length);
            hits.Add(new Hit
            {
                Owner = owner, Kind = kind, Where = where,
                Snippet = snippet, MatchStart = start, MatchLength = q.Length, ChildId = childId
            });
        }

        IEnumerable<HierarchyItem> all = data.Equipment.Cast<HierarchyItem>()
            .Concat(data.Tasks).Concat(data.Procedures).Concat(data.Vessels);

        foreach (var item in all)
        {
            if (hits.Count >= maxResults) break;
            Add(item, HitKind.Item, "Name", item.Name);
            // Tags are a navigation aid (like the item's name), so they stay searchable even for
            // locked items — they carry no protected content.
            if (item.Tags.Count > 0)
                Add(item, HitKind.Item, "Tags", string.Join(", ", item.Tags));

            // A locked (not-unlocked-this-session) item exposes only its Name to search — its
            // description, notes, files and child content stay hidden until it's unlocked, so the
            // per-entry lock can't be bypassed by reading search snippets.
            if (lockedOwnerIds != null && lockedOwnerIds.Contains(item.Id))
                continue;

            Add(item, HitKind.Item, "Description", item.Description);
            Add(item, HitKind.Item, "Notes", PlainTextFromXaml(item.Container?.RichTextXaml));
            if (item.Container != null)
            {
                foreach (var f in item.Container.Files)
                {
                    Add(item, HitKind.File, $"File › {f.Kind}", f.Name);
                    Add(item, HitKind.File, $"File › {f.Kind} › Path", f.Path);
                }
            }

            switch (item)
            {
                case Equipment eq:
                    foreach (var c in eq.Components)
                    {
                        Add(eq, HitKind.Component, $"Component › Name", c.Name, c.Id);
                        Add(eq, HitKind.Component, $"Component › Notes", c.Notes, c.Id);
                        Add(eq, HitKind.Component, $"Component › Container", PlainTextFromXaml(c.Container?.RichTextXaml), c.Id);
                        if (c.Container != null)
                            foreach (var f in c.Container.Files)
                                Add(eq, HitKind.Component, $"Component › File", f.Name, c.Id);
                    }
                    break;
                case TaskItem t:
                    Walk(t, t, Add);
                    break;
                case Procedure p:
                    foreach (var step in p.Steps)
                    {
                        Add(p, HitKind.Step, "Step › Title", step.Title, step.Id);
                        Add(p, HitKind.Step, "Step › Container", PlainTextFromXaml(step.Container?.RichTextXaml), step.Id);
                        if (step.Container != null)
                            foreach (var f in step.Container.Files)
                                Add(p, HitKind.Step, "Step › File", f.Name, step.Id);
                    }
                    break;
            }
        }
        return hits;
    }

    private static void Walk(TaskItem owner, TaskItem t, Action<HierarchyItem, HitKind, string, string, Guid?> add)
    {
        foreach (var st in t.Subtasks)
        {
            add(owner, HitKind.Subtask, "Subtask › Name", st.Name, st.Id);
            add(owner, HitKind.Subtask, "Subtask › Description", st.Description, st.Id);
            add(owner, HitKind.Subtask, "Subtask › Container", PlainTextFromXaml(st.Container?.RichTextXaml), st.Id);
            if (st.Container != null)
                foreach (var f in st.Container.Files)
                    add(owner, HitKind.Subtask, "Subtask › File", f.Name, st.Id);
            Walk(owner, st, add);
        }
    }

    private static (string snippet, int matchStart) MakeSnippet(string text, int idx, int len)
    {
        const int around = 60;
        var start = Math.Max(0, idx - around);
        var end = Math.Min(text.Length, idx + len + around);
        var sb = new StringBuilder();
        if (start > 0) sb.Append('…');
        var prefix = sb.Length;
        sb.Append(text, start, end - start);
        if (end < text.Length) sb.Append('…');
        // Collapse internal whitespace runs so the snippet stays compact.
        var compact = System.Text.RegularExpressions.Regex.Replace(sb.ToString(), @"\s+", " ");
        // Recompute match offset after collapse.
        var newIdx = compact.IndexOf(text.Substring(idx, len), StringComparison.OrdinalIgnoreCase);
        if (newIdx < 0) newIdx = prefix + (idx - start);
        return (compact, newIdx);
    }

    /// <summary>Cheap FlowDocument-XAML to plain-text extractor. We only need the text
    /// nodes for searching; full parsing into a FlowDocument is far too expensive for
    /// bulk scans across thousands of containers.</summary>
    public static string PlainTextFromXaml(string? xaml)
    {
        if (string.IsNullOrEmpty(xaml)) return "";
        try
        {
            using var sr = new StringReader(xaml);
            using var xr = XmlReader.Create(sr, new XmlReaderSettings { IgnoreWhitespace = false });
            var sb = new StringBuilder(xaml.Length);
            while (xr.Read())
            {
                if (xr.NodeType == XmlNodeType.Text || xr.NodeType == XmlNodeType.SignificantWhitespace)
                {
                    sb.Append(xr.Value);
                    sb.Append(' ');
                }
                else if (xr.NodeType == XmlNodeType.Element &&
                         (xr.LocalName is "Paragraph" or "LineBreak" or "ListItem"))
                {
                    sb.Append(' ');
                }
            }
            return sb.ToString();
        }
        catch
        {
            return System.Text.RegularExpressions.Regex.Replace(xaml, "<[^>]+>", " ");
        }
    }
}
