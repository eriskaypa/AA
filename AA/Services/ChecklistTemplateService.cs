using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Linq;
using AA.Models;

namespace AA.Services;

/// <summary>Captures a live checklist (procedure steps, task subtasks, or a crew member's checklist)
/// into a reusable <see cref="ChecklistTemplate"/> and applies a saved template back onto any of those
/// collections. Templates are a "full copy": title, duration, schedulable flag and the rich-text +
/// file-bank container (notes/files) — but not deadlines or done state (those are per-instance).</summary>
public static class ChecklistTemplateService
{
    // ---- Capture (save) ----

    public static ChecklistTemplate CaptureFromSteps(string name, IEnumerable<ChecklistStep> steps) =>
        new()
        {
            Name = name.Trim(),
            Items = new ObservableCollection<ChecklistTemplateItem>(steps.Select(s => new ChecklistTemplateItem
            {
                Title = s.Title,
                DurationMinutes = s.DurationMinutes,
                IsJob = s.IsJob,
                Container = CloneContainer(s.Container)
            }))
        };

    public static ChecklistTemplate CaptureFromSubtasks(string name, IEnumerable<TaskItem> subtasks) =>
        new()
        {
            Name = name.Trim(),
            Items = new ObservableCollection<ChecklistTemplateItem>(subtasks.Select(t => new ChecklistTemplateItem
            {
                Title = t.Name,
                DurationMinutes = t.DurationMinutes,
                IsJob = t.IsJob,
                Container = CloneContainer(t.Container)
            }))
        };

    // ---- Apply (load) ----

    /// <summary>Append (or replace) a template's items onto a checklist-step collection.</summary>
    public static int ApplyToSteps(ChecklistTemplate t, ObservableCollection<ChecklistStep> target, bool replace)
    {
        if (replace) target.Clear();
        foreach (var it in t.Items)
            target.Add(new ChecklistStep
            {
                Title = it.Title,
                DurationMinutes = it.DurationMinutes,
                IsJob = it.IsJob,
                Container = CloneContainer(it.Container)
            });
        return t.Items.Count;
    }

    /// <summary>Append (or replace) a template's items onto a task-subtask collection.</summary>
    public static int ApplyToSubtasks(ChecklistTemplate t, ObservableCollection<TaskItem> target, bool replace)
    {
        if (replace) target.Clear();
        foreach (var it in t.Items)
            target.Add(new TaskItem
            {
                Name = it.Title,
                DurationMinutes = it.DurationMinutes,
                IsJob = it.IsJob,
                Container = CloneContainer(it.Container)
            });
        return t.Items.Count;
    }

    /// <summary>Deep-copy a saved list (new Id, given name, same group), cloning every item's container.</summary>
    public static ChecklistTemplate Clone(ChecklistTemplate t, string newName) => new()
    {
        Name = newName,
        GroupId = t.GroupId,
        Items = new ObservableCollection<ChecklistTemplateItem>(t.Items.Select(it => new ChecklistTemplateItem
        {
            Title = it.Title,
            DurationMinutes = it.DurationMinutes,
            IsJob = it.IsJob,
            Container = CloneContainer(it.Container)
        }))
    };

    // ---- Editing a saved list itself (round-trip through the shared step builder) ----

    /// <summary>Materialise a template's items as editable <see cref="ChecklistStep"/>s (Title, Duration,
    /// IsJob, cloned Container) so the shared checklist builder can edit them.</summary>
    public static ObservableCollection<ChecklistStep> ToSteps(ChecklistTemplate t) =>
        new(t.Items.Select(it => new ChecklistStep
        {
            Title = it.Title,
            DurationMinutes = it.DurationMinutes,
            IsJob = it.IsJob,
            Container = CloneContainer(it.Container)
        }));

    /// <summary>Rebuild a template's items from edited steps (dropping per-instance deadline/done —
    /// a template stores titles, durations, schedulable flag and notes/files only).</summary>
    public static void WriteBackFromSteps(ChecklistTemplate t, IEnumerable<ChecklistStep> steps)
    {
        t.Items.Clear();
        foreach (var s in steps)
            t.Items.Add(new ChecklistTemplateItem
            {
                Title = s.Title,
                DurationMinutes = s.DurationMinutes,
                IsJob = s.IsJob,
                Container = CloneContainer(s.Container)
            });
    }

    // ---- Deep copy of a container (rich text + file bank) ----

    /// <summary>Deep-copy a container so a template owns an independent copy of the notes and file list.
    /// File items reference the same relative path in the shared <c>files/</c> folder (the physical file
    /// is bundled with the save either way), so no attachment is duplicated on disk.</summary>
    public static Container CloneContainer(Container? src)
    {
        var dst = new Container();
        if (src == null) return dst;
        dst.RichTextXaml = src.RichTextXaml;
        dst.IsLocked = src.IsLocked;
        foreach (var f in src.Files) dst.Files.Add(CloneFile(f));
        foreach (var id in src.SharedWithContainerIds) dst.SharedWithContainerIds.Add(id);
        return dst;
    }

    private static FileItem CloneFile(FileItem f)
    {
        var c = new FileItem
        {
            Name = f.Name,
            Path = f.Path,
            Kind = f.Kind,
            Added = f.Added,
            IsLink = f.IsLink,
            LinkInPlace = f.LinkInPlace
        };
        foreach (var id in f.LinkedItemIds) c.LinkedItemIds.Add(id);
        return c;
    }
}
