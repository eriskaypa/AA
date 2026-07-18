using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.RegularExpressions;
using AA.Models;

namespace AA.Services;

/// <summary>Builds a deep, hierarchical diff between the currently-loaded data and an incoming
/// database so the user can review exactly what an import would add, change, or remove — down to
/// individual fields, files, subtasks, components, steps and links — before it overwrites anything.</summary>
public static class DataDiff
{
    public enum Change { Added, Removed, Changed }

    public sealed class Node
    {
        public Change Change { get; init; }
        public string Text { get; init; } = "";
        public List<Node> Children { get; } = new();

        public Node() { }
        public Node(Change change, string text) { Change = change; Text = text; }
        public Node With(IEnumerable<Node> kids) { Children.AddRange(kids); return this; }
    }

    public sealed class Result
    {
        public List<Node> Roots { get; } = new();
        public int Added, Removed, Changed;
        public bool HasChanges => Roots.Count > 0;
    }

    public static Result Compare(AppData current, AppData incoming)
    {
        var r = new Result();

        // Name lookup across both databases so linked-id changes can be shown by name.
        var names = new Dictionary<Guid, string>();
        foreach (var i in Items(current)) names[i.Id] = i.Name;
        foreach (var i in Items(incoming)) names[i.Id] = i.Name;

        var cur = new Dictionary<Guid, HierarchyItem>();
        foreach (var i in Items(current)) cur[i.Id] = i;
        var inc = new Dictionary<Guid, HierarchyItem>();
        foreach (var i in Items(incoming)) inc[i.Id] = i;

        foreach (var kv in inc)
            if (!cur.ContainsKey(kv.Key))
            {
                r.Added++;
                r.Roots.Add(new Node(Change.Added, Root(kv.Value)).With(ContentChildren(kv.Value, Change.Added, names)));
            }

        foreach (var kv in cur)
            if (!inc.ContainsKey(kv.Key))
            {
                r.Removed++;
                r.Roots.Add(new Node(Change.Removed, Root(kv.Value)).With(ContentChildren(kv.Value, Change.Removed, names)));
            }

        foreach (var kv in inc)
            if (cur.TryGetValue(kv.Key, out var a))
            {
                var kids = CompareItem(a, kv.Value, names);
                if (kids.Count > 0)
                {
                    r.Changed++;
                    r.Roots.Add(new Node(Change.Changed, Root(kv.Value)).With(kids));
                }
            }

        r.Roots.Sort((x, y) =>
        {
            int o = Order(x.Change).CompareTo(Order(y.Change));
            return o != 0 ? o : string.Compare(x.Text, y.Text, StringComparison.OrdinalIgnoreCase);
        });
        return r;
    }

    private static int Order(Change c) => c switch { Change.Added => 0, Change.Changed => 1, _ => 2 };

    private static IEnumerable<HierarchyItem> Items(AppData d)
        => d.Equipment.Cast<HierarchyItem>().Concat(d.Tasks).Concat(d.Procedures).Concat(d.Vessels);

    private static string KindLabel(ItemKind k) => k == ItemKind.Equipment ? "Equipment/Area" : k.ToString();
    private static string Root(HierarchyItem i) => $"[{KindLabel(i.Kind)}] {i.Name}";

    // ---- whole-item content listing (for an added or removed item) ----
    private static List<Node> ContentChildren(HierarchyItem i, Change c, Dictionary<Guid, string> names)
    {
        var n = new List<Node>();
        foreach (var f in i.Container?.Files ?? Enumerable.Empty<FileItem>())
            n.Add(new Node(c, $"file: {f.Name}"));
        switch (i)
        {
            case TaskItem t:
                foreach (var s in t.Subtasks)
                    n.Add(new Node(c, $"subtask: {s.Name}").With(TaskContentChildren(s, c)));
                break;
            case Equipment e:
                foreach (var comp in e.Components)
                    n.Add(new Node(c, $"component: {comp.Name}").With(ComponentContentChildren(comp, c)));
                foreach (var id in e.ProcedureIds) n.Add(new Node(c, $"linked procedure: {Name(names, id)}"));
                foreach (var id in e.TaskIds) n.Add(new Node(c, $"linked task: {Name(names, id)}"));
                break;
            case Procedure p:
                foreach (var st in p.Steps)
                    n.Add(new Node(c, $"step: {st.Title}").With(StepContentChildren(st, c, names)));
                break;
        }
        return n;
    }

    private static List<Node> TaskContentChildren(TaskItem t, Change c)
    {
        var n = new List<Node>();
        foreach (var f in t.Container?.Files ?? Enumerable.Empty<FileItem>()) n.Add(new Node(c, $"file: {f.Name}"));
        foreach (var s in t.Subtasks) n.Add(new Node(c, $"subtask: {s.Name}").With(TaskContentChildren(s, c)));
        return n;
    }
    private static List<Node> ComponentContentChildren(Component comp, Change c)
        => (comp.Container?.Files ?? Enumerable.Empty<FileItem>()).Select(f => new Node(c, $"file: {f.Name}")).ToList();
    private static List<Node> StepContentChildren(ChecklistStep st, Change c, Dictionary<Guid, string> names)
    {
        var n = new List<Node>();
        foreach (var f in st.Container?.Files ?? Enumerable.Empty<FileItem>()) n.Add(new Node(c, $"file: {f.Name}"));
        foreach (var id in st.TaskIds) n.Add(new Node(c, $"linked task: {Name(names, id)}"));
        foreach (var id in st.EquipmentIds) n.Add(new Node(c, $"linked equipment/area: {Name(names, id)}"));
        return n;
    }

    // ---- per-item change comparison ----
    private static List<Node> CompareItem(HierarchyItem a, HierarchyItem b, Dictionary<Guid, string> names)
    {
        var n = new List<Node>();
        AddHierarchyFields(a, b, n);
        switch (b)
        {
            case TaskItem tb when a is TaskItem ta:
                if (ta.Deadline != tb.Deadline) n.Add(Field($"deadline: {Fmt(ta.Deadline)} → {Fmt(tb.Deadline)}"));
                if (ta.RangeStart != tb.RangeStart) n.Add(Field($"start: {Fmt(ta.RangeStart)} → {Fmt(tb.RangeStart)}"));
                if (ta.Recurrence != tb.Recurrence) n.Add(Field($"recurrence: {ta.Recurrence} → {tb.Recurrence}"));
                if (ta.Status != tb.Status) n.Add(Field($"status: {ta.Status} → {tb.Status}"));
                DiffTasks(ta.Subtasks, tb.Subtasks, names, n, "subtask");
                break;
            case Equipment eb when a is Equipment ea:
                DiffComponents(ea.Components, eb.Components, n);
                DiffLinks(ea.ProcedureIds, eb.ProcedureIds, names, n, "linked procedure");
                DiffLinks(ea.TaskIds, eb.TaskIds, names, n, "linked task");
                break;
            case Procedure pb when a is Procedure pa:
                DiffSteps(pa.Steps, pb.Steps, names, n);
                break;
        }
        return n;
    }

    private static void AddHierarchyFields(HierarchyItem a, HierarchyItem b, List<Node> n)
    {
        if (a.Name != b.Name) n.Add(Field($"name: \"{a.Name}\" → \"{b.Name}\""));
        if ((a.Description ?? "") != (b.Description ?? ""))
            n.Add(Field($"description: \"{Snip(a.Description)}\" → \"{Snip(b.Description)}\""));
        var an = PlainText(a.Container?.RichTextXaml);
        var bn = PlainText(b.Container?.RichTextXaml);
        if (an != bn) n.Add(Field($"notes: \"{Snip(an)}\" → \"{Snip(bn)}\""));
        DiffFiles(a.Container, b.Container, n);
    }

    private static void DiffFiles(Container? a, Container? b, List<Node> n)
    {
        var af = (a?.Files ?? Enumerable.Empty<FileItem>()).ToDictionary(f => f.Name + "|" + f.Path, f => f);
        var bf = (b?.Files ?? Enumerable.Empty<FileItem>()).ToDictionary(f => f.Name + "|" + f.Path, f => f);
        foreach (var kv in bf) if (!af.ContainsKey(kv.Key)) n.Add(new Node(Change.Added, $"file: {kv.Value.Name}"));
        foreach (var kv in af) if (!bf.ContainsKey(kv.Key)) n.Add(new Node(Change.Removed, $"file: {kv.Value.Name}"));
    }

    private static void DiffTasks(IEnumerable<TaskItem> a, IEnumerable<TaskItem> b, Dictionary<Guid, string> names, List<Node> n, string label)
    {
        var aById = ById(a, t => t.Id);
        var bById = ById(b, t => t.Id);
        foreach (var kv in bById)
            if (!aById.ContainsKey(kv.Key)) n.Add(new Node(Change.Added, $"{label}: {kv.Value.Name}").With(TaskContentChildren(kv.Value, Change.Added)));
        foreach (var kv in aById)
            if (!bById.ContainsKey(kv.Key)) n.Add(new Node(Change.Removed, $"{label}: {kv.Value.Name}").With(TaskContentChildren(kv.Value, Change.Removed)));
        foreach (var kv in bById)
            if (aById.TryGetValue(kv.Key, out var ta))
            {
                var kids = CompareItem(ta, kv.Value, names);
                if (kids.Count > 0) n.Add(new Node(Change.Changed, $"{label}: {kv.Value.Name}").With(kids));
            }
    }

    private static void DiffComponents(IEnumerable<Component> a, IEnumerable<Component> b, List<Node> n)
    {
        var aById = ById(a, c => c.Id);
        var bById = ById(b, c => c.Id);
        foreach (var kv in bById)
            if (!aById.ContainsKey(kv.Key)) n.Add(new Node(Change.Added, $"component: {kv.Value.Name}").With(ComponentContentChildren(kv.Value, Change.Added)));
        foreach (var kv in aById)
            if (!bById.ContainsKey(kv.Key)) n.Add(new Node(Change.Removed, $"component: {kv.Value.Name}").With(ComponentContentChildren(kv.Value, Change.Removed)));
        foreach (var kv in bById)
            if (aById.TryGetValue(kv.Key, out var ca))
            {
                var kids = new List<Node>();
                if (ca.Name != kv.Value.Name) kids.Add(Field($"name: \"{ca.Name}\" → \"{kv.Value.Name}\""));
                if ((ca.Notes ?? "") != (kv.Value.Notes ?? "")) kids.Add(Field($"notes line: \"{Snip(ca.Notes)}\" → \"{Snip(kv.Value.Notes)}\""));
                var an = PlainText(ca.Container?.RichTextXaml);
                var bn = PlainText(kv.Value.Container?.RichTextXaml);
                if (an != bn) kids.Add(Field($"notes: \"{Snip(an)}\" → \"{Snip(bn)}\""));
                DiffFiles(ca.Container, kv.Value.Container, kids);
                if (kids.Count > 0) n.Add(new Node(Change.Changed, $"component: {kv.Value.Name}").With(kids));
            }
    }

    private static void DiffSteps(IEnumerable<ChecklistStep> a, IEnumerable<ChecklistStep> b, Dictionary<Guid, string> names, List<Node> n)
    {
        var aById = ById(a, s => s.Id);
        var bById = ById(b, s => s.Id);
        foreach (var kv in bById)
            if (!aById.ContainsKey(kv.Key)) n.Add(new Node(Change.Added, $"step: {kv.Value.Title}").With(StepContentChildren(kv.Value, Change.Added, names)));
        foreach (var kv in aById)
            if (!bById.ContainsKey(kv.Key)) n.Add(new Node(Change.Removed, $"step: {kv.Value.Title}").With(StepContentChildren(kv.Value, Change.Removed, names)));
        foreach (var kv in bById)
            if (aById.TryGetValue(kv.Key, out var sa))
            {
                var sb = kv.Value;
                var kids = new List<Node>();
                if (sa.Title != sb.Title) kids.Add(Field($"title: \"{sa.Title}\" → \"{sb.Title}\""));
                if (sa.Done != sb.Done) kids.Add(Field($"done: {sa.Done} → {sb.Done}"));
                var an = PlainText(sa.Container?.RichTextXaml);
                var bn = PlainText(sb.Container?.RichTextXaml);
                if (an != bn) kids.Add(Field($"notes: \"{Snip(an)}\" → \"{Snip(bn)}\""));
                DiffFiles(sa.Container, sb.Container, kids);
                DiffLinks(sa.TaskIds, sb.TaskIds, names, kids, "linked task");
                DiffLinks(sa.EquipmentIds, sb.EquipmentIds, names, kids, "linked equipment/area");
                if (kids.Count > 0) n.Add(new Node(Change.Changed, $"step: {sb.Title}").With(kids));
            }
    }

    private static void DiffLinks(IEnumerable<Guid> a, IEnumerable<Guid> b, Dictionary<Guid, string> names, List<Node> n, string label)
    {
        var aset = a.ToHashSet();
        var bset = b.ToHashSet();
        foreach (var id in bset) if (!aset.Contains(id)) n.Add(new Node(Change.Added, $"{label}: {Name(names, id)}"));
        foreach (var id in aset) if (!bset.Contains(id)) n.Add(new Node(Change.Removed, $"{label}: {Name(names, id)}"));
    }

    // ---- helpers ----
    private static Node Field(string text) => new(Change.Changed, text);

    private static Dictionary<Guid, T> ById<T>(IEnumerable<T> items, Func<T, Guid> id)
    {
        var d = new Dictionary<Guid, T>();
        foreach (var i in items) d[id(i)] = i;   // last wins (ids are unique in practice)
        return d;
    }

    private static string Name(Dictionary<Guid, string> names, Guid id)
        => names.TryGetValue(id, out var n) ? n : "(unknown)";

    private static string Fmt(DateTime? d) => d?.ToString("yyyy-MM-dd") ?? "(none)";

    private static string Snip(string? s)
    {
        s = (s ?? "").Replace("\r", " ").Replace("\n", " ").Trim();
        return s.Length <= 40 ? s : s.Substring(0, 40) + "…";
    }

    private static string PlainText(string? xaml)
    {
        if (string.IsNullOrEmpty(xaml)) return "";
        var noTags = Regex.Replace(xaml, "<[^>]+>", " ");
        var decoded = System.Net.WebUtility.HtmlDecode(noTags);
        return Regex.Replace(decoded, "\\s+", " ").Trim();
    }
}
