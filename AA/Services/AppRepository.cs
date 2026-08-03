using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Linq;
using System.Text.Json;
using System.Text.Json.Serialization;
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

    /// <summary>When true, ALL persistence is suppressed (no autosave, no explicit Save). Set when the
    /// data file was present but unreadable at load, so the app's empty/placeholder model can never be
    /// written back over the real file on disk.</summary>
    public bool SuspendSaving { get; set; }

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
        if (SuspendSaving || !_dirty) return;
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
        if (SuspendSaving) return;   // read-only safe mode — never write over an unreadable file
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

    /// <summary>Detach this repository before it is discarded (a data reload/import swaps in a new one):
    /// stop the debounce timer, suspend any further saving, and drop the Saved subscribers. Without this
    /// the outgoing repo's still-running <see cref="DispatcherTimer"/> keeps it (and its whole data graph)
    /// alive and can tick after the swap, writing its now-discarded data over the freshly-loaded file.</summary>
    public void Detach()
    {
        SuspendSaving = true;
        _debounce.Stop();
        Saved = null;
    }

    /// <summary>Schedule a save shortly after the last edit; coalesces rapid changes.</summary>
    public void MarkDirty()
    {
        if (SuspendSaving) return;
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

    // ---------- Trash (soft delete) + Undo ----------

    private const int MaxTrashItems = 200;
    private static readonly TimeSpan TrashRetention = TimeSpan.FromDays(90);
    private static readonly JsonSerializerOptions TrashOpts = new()
    {
        ReferenceHandler = ReferenceHandler.IgnoreCycles,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull
    };

    private static string TrashType(ItemKind kind) => kind switch
    {
        ItemKind.Equipment => "Equipment",
        ItemKind.Task => "Task",
        ItemKind.Procedure => "Procedure",
        ItemKind.Vessel => "Vessel",
        _ => ""
    };

    /// <summary>Soft-delete a top-level hierarchy item: capture it (full subtree) into the Trash, remove
    /// it from its live collection, and scrub dangling references. Reversible via <see cref="RestoreTrash"/>
    /// / <see cref="UndoLastDelete"/>. Returns the Trash entry (or null if the kind isn't trashable).</summary>
    public TrashedItem? TrashHierarchyItem(HierarchyItem item)
    {
        var type = TrashType(item.Kind);
        if (type.Length == 0) return null;
        var ti = new TrashedItem
        {
            ItemType = type,
            ItemId = item.Id,
            Name = item.Name,
            KindLabel = KindLabel(item.Kind),
            PayloadJson = JsonSerializer.Serialize(item, item.GetType(), TrashOpts)
        };
        switch (item)
        {
            case Equipment eq: Data.Equipment.Remove(eq); break;
            case TaskItem t: Data.Tasks.Remove(t); break;
            case Procedure p: Data.Procedures.Remove(p); break;
            case Vessel v: Data.Vessels.Remove(v); break;
            default: return null;
        }
        // References are scrubbed only when the item is PERMANENTLY removed (permanent delete / prune), so
        // a restore brings the relationship graph back intact (both sides of two-way links, one-way
        // Equipment→Procedure/Task links, and step links).
        AddToTrash(ti);
        LogRemoved(KindLabel(item.Kind), item.Name, "moved to Trash");
        MarkDirty();
        return ti;
    }

    /// <summary>Soft-delete a crew member into the Trash.</summary>
    public TrashedItem TrashCrew(CrewMember m)
    {
        var ti = new TrashedItem
        {
            ItemType = "Crew",
            ItemId = m.Id,
            Name = string.IsNullOrWhiteSpace(m.FullName) ? m.LastName : m.FullName,
            KindLabel = "Crew member",
            PayloadJson = JsonSerializer.Serialize(m, TrashOpts)
        };
        Data.Crew.Remove(m);
        AddToTrash(ti);
        LogRemoved("Crew member", ti.Name, "moved to Trash");
        MarkDirty();
        return ti;
    }

    private void AddToTrash(TrashedItem ti)
    {
        Data.Trash.Add(ti);
        PruneTrash();
    }

    /// <summary>Enforce the Trash retention window (90 days) and count cap (200), oldest first, so it can
    /// never bloat the save file / shared bundle. Safe to call any time — notably once on load, so
    /// retention is honoured even if the user stops deleting things (the add-time prune alone wouldn't).
    /// A permanently-removed item has its dangling references scrubbed.</summary>
    public void PruneTrash()
    {
        bool changed = false;
        var cutoff = DateTime.UtcNow - TrashRetention;
        for (int i = Data.Trash.Count - 1; i >= 0; i--)
            if (Data.Trash[i].DeletedUtc < cutoff) { EvictAt(i); changed = true; }
        while (Data.Trash.Count > MaxTrashItems)
        {
            var oldest = Data.Trash.OrderBy(t => t.DeletedUtc).First();
            EvictAt(Data.Trash.IndexOf(oldest));
            changed = true;
        }
        if (changed) MarkDirty();
    }

    private void EvictAt(int i)
    {
        PurgeReferences(Data.Trash[i].ItemId);   // gone for good — scrub any dangling links now
        Data.Trash.RemoveAt(i);
    }

    /// <summary>Restore a trashed item to its original collection. Returns its ItemType
    /// ("Equipment"/"Task"/"Procedure"/"Vessel"/"Crew") so the caller can refresh the right page,
    /// or null if it couldn't be restored.</summary>
    public string? RestoreTrash(TrashedItem ti)
    {
        try
        {
            switch (ti.ItemType)
            {
                case "Equipment":
                    var eq = JsonSerializer.Deserialize<Equipment>(ti.PayloadJson, TrashOpts);
                    if (eq == null) return null;
                    if (!Data.Equipment.Any(x => x.Id == eq.Id)) Data.Equipment.Add(eq);
                    break;
                case "Task":
                    var t = JsonSerializer.Deserialize<TaskItem>(ti.PayloadJson, TrashOpts);
                    if (t == null) return null;
                    if (!Data.Tasks.Any(x => x.Id == t.Id)) Data.Tasks.Add(t);
                    break;
                case "Procedure":
                    var p = JsonSerializer.Deserialize<Procedure>(ti.PayloadJson, TrashOpts);
                    if (p == null) return null;
                    if (!Data.Procedures.Any(x => x.Id == p.Id)) Data.Procedures.Add(p);
                    break;
                case "Vessel":
                    var v = JsonSerializer.Deserialize<Vessel>(ti.PayloadJson, TrashOpts);
                    if (v == null) return null;
                    if (!Data.Vessels.Any(x => x.Id == v.Id)) Data.Vessels.Add(v);
                    break;
                case "Crew":
                    var cm = JsonSerializer.Deserialize<CrewMember>(ti.PayloadJson, TrashOpts);
                    if (cm == null) return null;
                    if (!Data.Crew.Any(x => x.Id == cm.Id)) Data.Crew.Add(cm);
                    break;
                default: return null;
            }
        }
        catch { return null; }
        Data.Trash.Remove(ti);
        LogAdded(ti.KindLabel, ti.Name, "restored from Trash");
        MarkDirty();
        return ti.ItemType;
    }

    /// <summary>Restore the most recently deleted item (Ctrl+Z). Returns its ItemType or null if the
    /// Trash is empty / restore failed.</summary>
    public string? UndoLastDelete()
    {
        var ti = Data.Trash.OrderByDescending(t => t.DeletedUtc).FirstOrDefault();
        return ti == null ? null : RestoreTrash(ti);
    }

    public void PurgeTrash(TrashedItem ti)
    {
        if (Data.Trash.Remove(ti)) { PurgeReferences(ti.ItemId); MarkDirty(); }
    }

    public void EmptyTrash()
    {
        if (Data.Trash.Count == 0) return;
        foreach (var ti in Data.Trash.ToList()) PurgeReferences(ti.ItemId);
        Data.Trash.Clear();
        MarkDirty();
    }

    // ---------- Recurrence: regenerate the next occurrence on completion ----------

    private static DateTime NextOccurrence(DateTime from, RecurrenceKind r) => r switch
    {
        RecurrenceKind.Daily => from.AddDays(1),
        RecurrenceKind.Weekly => from.AddDays(7),
        RecurrenceKind.Monthly => from.AddMonths(1),
        RecurrenceKind.Yearly => from.AddYears(1),
        _ => from
    };

    private static T DeepClone<T>(T obj) =>
        JsonSerializer.Deserialize<T>(JsonSerializer.Serialize(obj, TrashOpts), TrashOpts)!;

    /// <summary>Walk a completed recurring Task/Procedure and generate its next occurrence (once).
    /// A monthly fire-drill task, once ticked complete, re-appears with next month's due date instead
    /// of silently dropping off. Idempotent: the completed source is flagged so a re-save or a
    /// complete/uncomplete toggle never spawns duplicates. Scope: top-level Tasks and Procedures.
    /// Returns true if anything was generated (caller should refresh the affected pages).</summary>
    public bool ReconcileRecurrences()
    {
        bool changed = false;

        var newTasks = new List<TaskItem>();
        foreach (var t in Data.Tasks.ToList())
        {
            if (t.Recurrence == RecurrenceKind.None || !t.IsComplete || t.RecurrenceSpawned) continue;
            t.RecurrenceSpawned = true;                       // never spawn twice for this completion
            var clone = DeepClone(t);
            RenewTaskForNextOccurrence(clone);
            var oldDeadline = t.Deadline;
            var next = NextOccurrence(oldDeadline ?? DateTime.Today, t.Recurrence);
            // Preserve a working-range length if the source had one.
            if (t.RangeStart is DateTime rs && oldDeadline is DateTime dl && rs.Date < dl.Date)
                clone.RangeStart = next.AddDays(-(dl.Date - rs.Date).Days);
            else
                clone.RangeStart = null;
            clone.Deadline = next;
            // Shift subtask deadlines by the same amount so the new occurrence's children aren't born in the
            // past (else they'd read as immediately overdue in the due window / reminders).
            if (oldDeadline is DateTime od) ShiftTaskChildDeadlines(clone, next.Date - od.Date);
            newTasks.Add(clone);
            LogAdded("Task (recurring)", clone.Name, $"next {t.Recurrence} occurrence → {next:yyyy-MM-dd}");
            changed = true;
        }
        foreach (var nt in newTasks) Data.Tasks.Add(nt);

        var newProcs = new List<Procedure>();
        foreach (var p in Data.Procedures.ToList())
        {
            if (p.Recurrence == RecurrenceKind.None || p.Status != WorkStatus.Done || p.RecurrenceSpawned) continue;
            p.RecurrenceSpawned = true;
            var clone = DeepClone(p);
            RenewProcedureForNextOccurrence(clone);
            var oldDeadline = p.Deadline;
            var next = NextOccurrence(oldDeadline ?? DateTime.Today, p.Recurrence);
            clone.Deadline = next;
            // Shift step deadlines by the same delta so they don't resurface already overdue.
            if (oldDeadline is DateTime opd)
            {
                var delta = next.Date - opd.Date;
                foreach (var s in clone.Steps)
                    if (s.Deadline is DateTime sd) s.Deadline = sd.Add(delta);
            }
            newProcs.Add(clone);
            LogAdded("Procedure (recurring)", clone.Name, $"next {p.Recurrence} occurrence → {clone.Deadline:yyyy-MM-dd}");
            changed = true;
        }
        foreach (var np in newProcs) Data.Procedures.Add(np);

        if (changed) MarkDirty();
        return changed;
    }

    private static void RenewTaskForNextOccurrence(TaskItem t)
    {
        t.Id = Guid.NewGuid();
        if (t.Container != null) t.Container.Id = Guid.NewGuid();
        t.RecurrenceSpawned = false;
        t.ScheduledStart = null;
        t.IsComplete = false;             // also resets Status to Todo via the setter
        foreach (var st in t.Subtasks) RenewTaskForNextOccurrence(st);
    }

    /// <summary>Shift every subtask's deadline (and working-range start) by <paramref name="delta"/> so the
    /// regenerated occurrence's children keep their offset from the (advanced) parent deadline.</summary>
    private static void ShiftTaskChildDeadlines(TaskItem t, TimeSpan delta)
    {
        foreach (var st in t.Subtasks)
        {
            if (st.Deadline is DateTime d) st.Deadline = d.Add(delta);
            if (st.RangeStart is DateTime rs) st.RangeStart = rs.Add(delta);
            ShiftTaskChildDeadlines(st, delta);
        }
    }

    private static void RenewProcedureForNextOccurrence(Procedure p)
    {
        p.Id = Guid.NewGuid();
        if (p.Container != null) p.Container.Id = Guid.NewGuid();
        p.RecurrenceSpawned = false;
        p.ScheduledStart = null;
        p.Status = WorkStatus.Todo;
        foreach (var s in p.Steps)
        {
            s.Id = Guid.NewGuid();
            if (s.Container != null) s.Container.Id = Guid.NewGuid();
            s.Done = false;
            s.ScheduledStart = null;
        }
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
