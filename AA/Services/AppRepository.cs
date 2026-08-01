using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Linq;
using System.Windows.Threading;
using AA.Models;

namespace AA.Services;

/// <summary>App-wide repository tying together hierarchy items, with helpers for relationship lookups.</summary>
public class AppRepository
{
    public AppData Data { get; }

    private readonly DispatcherTimer _debounce;
    private bool _dirty;
    // Background writes are chained so they commit strictly in order (a newer save can't be overtaken
    // by an older one). Only ever assigned on the UI thread.
    private System.Threading.Tasks.Task _writeChain = System.Threading.Tasks.Task.CompletedTask;

    /// <summary>Raised after a successful (immediate or debounced) save.</summary>
    public event Action? Saved;

    public AppRepository(AppData data)
    {
        Data = data;
        _debounce = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(750) };
        _debounce.Tick += (_, _) => { _debounce.Stop(); BackgroundSaveIfDirty(); };
    }

    /// <summary>Debounced autosave: serialize on the UI thread (a consistent snapshot — the model can't
    /// change under us mid-serialize since edits are UI-thread too), then write to disk on a background
    /// thread so a large data file never freezes typing on disk I/O. Keeps typing responsive even as the
    /// note count grows into the tens/hundreds of thousands. Explicit <see cref="Save"/> stays synchronous.</summary>
    private async void BackgroundSaveIfDirty()
    {
        if (!_dirty) return;
        var prevStamp = Data.LastModified;
        Data.LastModified = DateTime.Now;
        _dirty = false;
        string json;
        try { json = DataStore.SerializeForSave(Data); }
        catch { Data.LastModified = prevStamp; _dirty = true; return; }   // transient hiccup — retry next change

        // On failure, restore the dirty flag AND the stamp so the on-disk file and the in-memory stamp
        // don't diverge (which could otherwise push a stale bundle over a newer shared save).
        try { await QueueWrite(json); Saved?.Invoke(); }
        catch { Data.LastModified = prevStamp; _dirty = true; }
    }

    /// <summary>Queue a write of <paramref name="json"/> after every write already queued, so writes commit
    /// strictly in order (the newest snapshot always lands last — no older write can clobber a newer one).
    /// The chain runs entirely on background threads (ConfigureAwait(false)), so a caller may safely block
    /// on the returned task from the UI thread without deadlocking.</summary>
    private System.Threading.Tasks.Task QueueWrite(string json)
    {
        var prev = _writeChain;
        var mine = System.Threading.Tasks.Task.Run(async () =>
        {
            try { await prev.ConfigureAwait(false); } catch { }
            DataStore.WriteData(json);
        });
        _writeChain = mine;
        return mine;
    }

    public IEnumerable<HierarchyItem> AllItems()
    {
        foreach (var e in Data.Equipment) yield return e;
        foreach (var t in Data.Tasks) yield return t;
        foreach (var p in Data.Procedures) yield return p;
        foreach (var v in Data.Vessels) yield return v;
    }

    public HierarchyItem? FindById(Guid id) => AllItems().FirstOrDefault(i => i.Id == id);

    /// <summary>Every rich-text / file-bank container in the model: top-level items, nested subtasks,
    /// equipment components and procedure steps.</summary>
    public IEnumerable<Container> AllContainers()
    {
        foreach (var eq in Data.Equipment)
        {
            if (eq.Container != null) yield return eq.Container;
            foreach (var c in eq.Components)
                if (c.Container != null) yield return c.Container;
        }
        foreach (var t in Data.Tasks)
            foreach (var c in WalkTaskContainers(t)) yield return c;
        foreach (var p in Data.Procedures)
        {
            if (p.Container != null) yield return p.Container;
            foreach (var step in p.Steps)
                if (step.Container != null) yield return step.Container;
        }
        foreach (var v in Data.Vessels)
            if (v.Container != null) yield return v.Container;
        foreach (var cm in Data.Crew)
            foreach (var s in cm.Checklist)
                if (s.Container != null) yield return s.Container;
        foreach (var tpl in Data.ChecklistTemplates)
            foreach (var it in tpl.Items)
                if (it.Container != null) yield return it.Container;
    }

    private static IEnumerable<Container> WalkTaskContainers(TaskItem t)
    {
        if (t.Container != null) yield return t.Container;
        foreach (var st in t.Subtasks)
            foreach (var c in WalkTaskContainers(st)) yield return c;
    }

    /// <summary>Every item tagged as a Job — top-level tasks, nested subtasks (recursive),
    /// procedure checklist steps, and crew-member checklist steps.</summary>
    public IEnumerable<IJob> AllJobs()
    {
        foreach (var t in Data.Tasks)
            foreach (var j in JobsInTask(t)) yield return j;
        foreach (var p in Data.Procedures)
        {
            if (p.IsJob) yield return p;
            foreach (var s in p.Steps)
                if (s.IsJob) yield return s;
        }
        foreach (var c in Data.Crew)
            foreach (var s in c.Checklist)
                if (s.IsJob) yield return s;
    }

    private static IEnumerable<IJob> JobsInTask(TaskItem t)
    {
        if (t.IsJob) yield return t;
        foreach (var st in t.Subtasks)
            foreach (var j in JobsInTask(st)) yield return j;
    }

    public string Label(Guid id)
    {
        var item = FindById(id);
        if (item == null) return "(missing)";
        return $"[{item.Kind}] {item.Name}";
    }

    public IEnumerable<HierarchyItem> RelatedItems(HierarchyItem item)
    {
        var ids = new HashSet<Guid>(item.RelatedIds);
        if (item is Equipment e)
        {
            foreach (var id in e.ProcedureIds) ids.Add(id);
            foreach (var id in e.TaskIds) ids.Add(id);
        }
        foreach (var id in ids)
        {
            var x = FindById(id);
            if (x != null) yield return x;
        }
    }

    /// <summary>Every item that references <paramref name="target"/> — Obsidian-style backlinks.
    /// Covers two-way <c>RelatedIds</c>, an Equipment/Area's linked procedures/tasks, and a procedure
    /// step's linked tasks/equipment. So a Task/Procedure can see who points at it, even for the
    /// one-way links that don't appear in its own relationship list.</summary>
    public IEnumerable<HierarchyItem> ReferencedBy(HierarchyItem target)
    {
        var id = target.Id;
        foreach (var i in AllItems())
        {
            if (i.Id == id) continue;
            bool refs = i.RelatedIds.Contains(id);
            if (!refs && i is Equipment eq) refs = eq.ProcedureIds.Contains(id) || eq.TaskIds.Contains(id);
            if (!refs && i is Procedure p) refs = p.Steps.Any(s => s.TaskIds.Contains(id) || s.EquipmentIds.Contains(id));
            if (refs) yield return i;
        }
    }

    /// <summary>Scrub every reference to <paramref name="deletedId"/> from all items so a deleted
    /// item leaves no dangling links. Covers two-way <c>RelatedIds</c>, an Equipment/Area's one-way
    /// <c>ProcedureIds</c>/<c>TaskIds</c>, and each procedure step's <c>TaskIds</c>/<c>EquipmentIds</c>.
    /// Without this, a deleted procedure/task lingers as a "(missing)" row and phantom backlink.</summary>
    public void PurgeReferences(Guid deletedId)
    {
        foreach (var item in AllItems())
        {
            item.RelatedIds.Remove(deletedId);
            if (item is Equipment eq)
            {
                eq.ProcedureIds.Remove(deletedId);
                eq.TaskIds.Remove(deletedId);
            }
            else if (item is Procedure p)
            {
                foreach (var step in p.Steps)
                {
                    step.TaskIds.Remove(deletedId);
                    step.EquipmentIds.Remove(deletedId);
                }
            }
        }
        // File-bank cross-links (FileItem.LinkedItemIds) also point at items by id, so scrub those
        // too — otherwise a deleted item lingers as a dangling link that is re-saved every time.
        foreach (var container in AllContainers())
            foreach (var f in container.Files)
                f.LinkedItemIds.Remove(deletedId);
    }

    public void AddRelation(HierarchyItem a, HierarchyItem b)
    {
        if (a.Id == b.Id) return;
        if (!a.RelatedIds.Contains(b.Id)) a.RelatedIds.Add(b.Id);
        if (!b.RelatedIds.Contains(a.Id)) b.RelatedIds.Add(a.Id);
    }

    public void RemoveRelation(HierarchyItem a, HierarchyItem b)
    {
        a.RelatedIds.Remove(b.Id);
        b.RelatedIds.Remove(a.Id);
    }

    // ---------- Activity log ----------

    private const int MaxLogEntries = 10000;

    /// <summary>Record that an entry was added, with a UTC timestamp.</summary>
    public void LogAdded(string kind, string name, string detail = "") => LogAction("Added", kind, name, detail);

    /// <summary>Record that an entry was removed, with a UTC timestamp.</summary>
    public void LogRemoved(string kind, string name, string detail = "") => LogAction("Removed", kind, name, detail);

    private void LogAction(string action, string kind, string name, string detail)
    {
        Data.Log.Add(new LogEntry
        {
            TimestampUtc = DateTime.UtcNow,
            Action = action,
            Kind = kind,
            Name = string.IsNullOrWhiteSpace(name) ? "(unnamed)" : name.Trim(),
            Detail = detail ?? ""
        });
        // Keep the log bounded so it never bloats the save file.
        while (Data.Log.Count > MaxLogEntries) Data.Log.RemoveAt(0);
        MarkDirty();
    }

    public static string KindLabel(ItemKind kind) => kind switch
    {
        ItemKind.Equipment => "Equipment/Area",
        ItemKind.Task => "Task",
        ItemKind.Procedure => "Procedure",
        ItemKind.Vessel => "Vessel",
        _ => kind.ToString()
    };

    /// <summary>Force an immediate, synchronous save (used on close and before critical operations so the
    /// data is on disk before we continue).</summary>
    public void Save()
    {
        _debounce.Stop();
        var prevStamp = Data.LastModified;
        Data.LastModified = DateTime.Now;   // stamp so imports can detect stale files
        string json;
        try { json = DataStore.SerializeForSave(Data); }
        catch { Data.LastModified = prevStamp; throw; }   // leave _dirty set; surface the error

        // Chain this write after any pending background write (so it lands last) and block until it's on
        // disk — Save() is the "make sure it's persisted now" path (close / before critical operations).
        // Only clear the dirty flag / report success once the write is CONFIRMED; on any failure or timeout
        // keep _dirty set and throw, so callers show their "save failed" UI and the autosave retries.
        try
        {
            if (!QueueWrite(json).Wait(15000))
            {
                Data.LastModified = prevStamp;
                throw new TimeoutException($"Timed out writing {DataStore.CurrentDataFile}.");
            }
        }
        catch (AggregateException ae) { Data.LastModified = prevStamp; throw ae.InnerException ?? ae; }

        _dirty = false;
        Saved?.Invoke();
    }

    /// <summary>Schedule a save shortly after the last edit; coalesces rapid changes.</summary>
    public void MarkDirty()
    {
        _dirty = true;
        _debounce.Stop();
        _debounce.Start();
    }

    public bool IsDirty => _dirty;

    /// <summary>Save now if any pending changes; safe to call repeatedly.</summary>
    public void FlushIfDirty()
    {
        if (_dirty) Save();
    }

    // ---------- Sidebar groups ----------

    public IEnumerable<ItemGroup> GroupsFor(ItemKind kind) =>
        Data.Groups.Where(g => g.Kind == kind);

    public ItemGroup CreateGroup(ItemKind kind, string name)
    {
        var g = new ItemGroup { Kind = kind, Name = string.IsNullOrWhiteSpace(name) ? "New group" : name.Trim() };
        Data.Groups.Add(g);
        return g;
    }

    public void RenameGroup(ItemGroup g, string newName)
    {
        if (string.IsNullOrWhiteSpace(newName)) return;
        g.Name = newName.Trim();
    }

    /// <summary>Delete a group and ungroup all items that referenced it.</summary>
    public void DeleteGroup(ItemGroup g)
    {
        foreach (var item in AllItems().Where(i => i.GroupId == g.Id))
            item.GroupId = null;
        Data.Groups.Remove(g);
    }

    public void AssignToGroup(IEnumerable<HierarchyItem> items, Guid? groupId)
    {
        foreach (var item in items) item.GroupId = groupId;
    }
}
