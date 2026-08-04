using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using AA.Models;
using AA.Services;

namespace AA.Sire;

/// <summary>Bridges the SIRE knowledge bank into AA's own hierarchy: turns a question, a section, or a
/// whole chapter into an AA Equipment / Task / Procedure (the "parent item"), carrying the SIRE detail in
/// its rich-text container, and spins off each offline-identified task as its own top-level AA Task,
/// cross-linked back to the parent.</summary>
public static class SireToAa
{
    public enum Kind { Procedure, Task, Equipment }

    public sealed record Result(int ItemsCreated, int TasksCreated, HierarchyItem? Primary, string Summary);

    // ---------- Public entry points ----------

    /// <summary>Add one SIRE question as the chosen AA kind, with its identified tasks as top-level Tasks.</summary>
    public static Result AddQuestion(AppRepository repo, SireQuestion q, Kind kind, bool createTopLevelTasks)
    {
        int items = 0, tasks = 0;
        var parent = CreateItem(repo, kind, $"SIRE Q{q.QuestionNumber} — {q.ShortQuestionText}", BuildQuestionXaml(q));
        items++;

        var identified = SireBank.GetIdentifiedTasks(q.QuestionNumber);
        // Represent the question's tasks as children of the parent (steps/subtasks/components)...
        AttachChildTasks(parent, identified);
        // ...and (Both mode) also as their own top-level AA Tasks, cross-linked back.
        if (createTopLevelTasks)
            tasks += SpawnTopLevelTasks(repo, parent, q, identified);

        repo.LogAdded(AppRepository.KindLabel(parent.Kind), parent.Name, $"from SIRE Q{q.QuestionNumber}");
        return new Result(items, tasks, parent,
            $"Added “{parent.Name}” as {kind}" + (tasks > 0 ? $" with {tasks} linked task(s)." : "."));
    }

    /// <summary>Add every question in a SIRE section under one parent of the chosen kind.</summary>
    public static Result AddSection(AppRepository repo, string section, Kind kind, bool createTopLevelTasks)
        => AddGroup(repo, SireBank.InSection(section).ToList(), kind, createTopLevelTasks, $"SIRE Section {section}");

    /// <summary>Add every question in a SIRE chapter under one parent of the chosen kind.</summary>
    public static Result AddChapter(AppRepository repo, string chapter, Kind kind, bool createTopLevelTasks)
    {
        var qs = SireBank.InChapter(chapter).ToList();
        var name = qs.Count > 0 ? $"SIRE Ch{chapter} — {qs[0].ChapterName}" : $"SIRE Ch{chapter}";
        return AddGroup(repo, qs, kind, createTopLevelTasks, name);
    }

    private static Result AddGroup(AppRepository repo, List<SireQuestion> qs, Kind kind, bool createTopLevelTasks, string parentName)
    {
        if (qs.Count == 0) return new Result(0, 0, null, "No questions found for that selection.");
        int items = 0, tasks = 0;
        var parent = CreateItem(repo, kind, parentName, BuildOverviewXaml(parentName, qs));
        items++;

        foreach (var q in qs)
        {
            // Each question becomes a child of the parent (checklist step / subtask / component)...
            AddQuestionChild(parent, q);
            var identified = SireBank.GetIdentifiedTasks(q.QuestionNumber);
            // ...and its identified tasks become top-level AA Tasks cross-linked to the parent.
            if (createTopLevelTasks)
                tasks += SpawnTopLevelTasks(repo, parent, q, identified);
        }

        repo.LogAdded(AppRepository.KindLabel(parent.Kind), parent.Name, $"from SIRE ({qs.Count} questions)");
        return new Result(items, tasks, parent,
            $"Added “{parent.Name}” as {kind} with {qs.Count} question(s)" + (tasks > 0 ? $" and {tasks} linked task(s)." : "."));
    }

    // ---------- Item creation ----------

    private static HierarchyItem CreateItem(AppRepository repo, Kind kind, string name, string bodyXaml)
    {
        HierarchyItem item = kind switch
        {
            Kind.Procedure => new Procedure { Name = name },
            Kind.Task => new TaskItem { Name = name },
            Kind.Equipment => new Equipment { Name = name },
            _ => new TaskItem { Name = name }
        };
        item.Container.RichTextXaml = bodyXaml;
        item.Tags.Add("SIRE");
        switch (item)
        {
            case Equipment e: repo.Data.Equipment.Add(e); break;
            case TaskItem t: repo.Data.Tasks.Add(t); break;
            case Procedure p: repo.Data.Procedures.Add(p); break;
        }
        return item;
    }

    /// <summary>Attach a question's identified tasks to the parent as native children:
    /// Procedure → checklist steps; Task → subtasks; Equipment → components.</summary>
    private static void AttachChildTasks(HierarchyItem parent, List<string> tasks)
    {
        switch (parent)
        {
            case Procedure p:
                foreach (var t in tasks) p.Steps.Add(new ChecklistStep { Title = t });
                break;
            case TaskItem parentTask:
                foreach (var t in tasks) parentTask.Subtasks.Add(new TaskItem { Name = t });
                break;
            case Equipment e:
                foreach (var t in tasks) e.Components.Add(new Component { Name = Truncate(t, 80), Notes = t });
                break;
        }
    }

    /// <summary>Add a whole question as a single child of a section/chapter parent (its short text becomes
    /// the child title; its full detail goes in the child's own container).</summary>
    private static void AddQuestionChild(HierarchyItem parent, SireQuestion q)
    {
        var title = $"Q{q.QuestionNumber} — {q.ShortQuestionText}";
        switch (parent)
        {
            case Procedure p:
                p.Steps.Add(new ChecklistStep { Title = title, Container = { RichTextXaml = BuildQuestionXaml(q) } });
                break;
            case TaskItem parentTask:
                parentTask.Subtasks.Add(new TaskItem { Name = title, Container = { RichTextXaml = BuildQuestionXaml(q) } });
                break;
            case Equipment e:
                e.Components.Add(new Component { Name = Truncate(title, 90), Notes = q.FullQuestionText, Container = { RichTextXaml = BuildQuestionXaml(q) } });
                break;
        }
    }

    /// <summary>Create one top-level AA Task per identified task, cross-linked to the parent both ways.</summary>
    private static int SpawnTopLevelTasks(AppRepository repo, HierarchyItem parent, SireQuestion q, List<string> identified)
    {
        int n = 0;
        foreach (var text in identified)
        {
            var task = new TaskItem { Name = text };
            task.Tags.Add("SIRE");
            task.Description = $"SIRE Q{q.QuestionNumber} — {q.ShortQuestionText}";
            repo.Data.Tasks.Add(task);
            repo.AddRelation(parent, task);                 // two-way RelatedIds
            if (parent is Equipment eq && !eq.TaskIds.Contains(task.Id)) eq.TaskIds.Add(task.Id);
            n++;
        }
        return n;
    }

    private static string Truncate(string s, int max) => s.Length <= max ? s : s[..max].TrimEnd() + "…";

    // ---------- FlowDocument XAML builders ----------

    private const string FlowNs = "http://schemas.microsoft.com/winfx/2006/xaml/presentation";

    public static string BuildQuestionXaml(SireQuestion q)
    {
        var sb = new StringBuilder();
        sb.Append($"<FlowDocument xmlns=\"{FlowNs}\">");
        Head(sb, $"SIRE 2.0 — Q {q.QuestionNumber}");
        Head(sb, q.ShortQuestionText);
        Body(sb, q.FullQuestionText);
        Meta(sb, $"Chapter: {q.ChapterDisplay}   |   Vessel types: {q.VesselTypesDisplay}" +
                 (string.IsNullOrWhiteSpace(q.RoviqSequence) ? "" : $"   |   ROVIQ: {q.RoviqSequence}"));
        Section(sb, "Data Source", q.DataSource);
        Section(sb, "Objective", q.Objective);
        Section(sb, "Industry Guidance", q.IndustryGuidance);
        Section(sb, "Inspection Guidance", q.InspectionGuidance);
        Section(sb, "Suggested Inspector Actions", q.SuggestedInspectorActions);
        Section(sb, "Expected Evidence", q.ExpectedEvidence);
        Section(sb, "Potential Negative Observation Grounds", q.PotentialNegativeObservationGrounds);
        Section(sb, "Publications", q.Publications);
        sb.Append("</FlowDocument>");
        return sb.ToString();
    }

    private static string BuildOverviewXaml(string title, List<SireQuestion> qs)
    {
        var sb = new StringBuilder();
        sb.Append($"<FlowDocument xmlns=\"{FlowNs}\">");
        Head(sb, title);
        Meta(sb, $"{qs.Count} SIRE question(s). Imported from the SIRE 2.0 Knowledge Bank.");
        foreach (var q in qs)
            sb.Append($"<Paragraph>{Esc($"Q {q.QuestionNumber} — {q.ShortQuestionText}")}</Paragraph>");
        sb.Append("</FlowDocument>");
        return sb.ToString();
    }

    private static void Head(StringBuilder sb, string text)
    {
        if (string.IsNullOrWhiteSpace(text)) return;
        sb.Append($"<Paragraph FontSize=\"15\"><Bold>{Esc(text)}</Bold></Paragraph>");
    }

    private static void Meta(StringBuilder sb, string text)
    {
        if (string.IsNullOrWhiteSpace(text)) return;
        sb.Append($"<Paragraph FontStyle=\"Italic\">{Esc(text)}</Paragraph>");
    }

    private static void Section(StringBuilder sb, string label, string? body)
    {
        if (string.IsNullOrWhiteSpace(body)) return;
        sb.Append($"<Paragraph Margin=\"0,8,0,2\"><Bold>{Esc(label)}</Bold></Paragraph>");
        Body(sb, body);
    }

    private static void Body(StringBuilder sb, string? text)
    {
        if (string.IsNullOrWhiteSpace(text)) return;
        // Preserve line breaks as <LineBreak/> inside a single paragraph.
        var parts = text.Replace("\r\n", "\n").Replace('\r', '\n').Split('\n');
        sb.Append("<Paragraph>");
        for (int i = 0; i < parts.Length; i++)
        {
            if (i > 0) sb.Append("<LineBreak/>");
            sb.Append(Esc(parts[i]));
        }
        sb.Append("</Paragraph>");
    }

    private static string Esc(string s)
    {
        var sb = new StringBuilder(s.Length + 8);
        foreach (var ch in s)
        {
            if (ch < 0x20 && ch != '\t' && ch != '\n' && ch != '\r') continue; // strip XML-1.0-illegal control chars
            switch (ch)
            {
                case '&': sb.Append("&amp;"); break;
                case '<': sb.Append("&lt;"); break;
                case '>': sb.Append("&gt;"); break;
                case '"': sb.Append("&quot;"); break;
                default: sb.Append(ch); break;
            }
        }
        return sb.ToString();
    }
}
