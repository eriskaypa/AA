using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Runtime.CompilerServices;
using System.Text.Json.Serialization;

namespace AA.Models;

public class NotifyBase : INotifyPropertyChanged
{
    public event PropertyChangedEventHandler? PropertyChanged;
    protected void OnChanged([CallerMemberName] string? name = null)
        => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
    protected bool Set<T>(ref T field, T value, [CallerMemberName] string? name = null)
    {
        if (EqualityComparer<T>.Default.Equals(field, value)) return false;
        field = value;
        OnChanged(name);
        return true;
    }
}

public enum FileKind { Document, Image, Video, Link, Other }

public class FileItem : NotifyBase
{
    public Guid Id { get; set; } = Guid.NewGuid();
    private string _name = "";
    public string Name { get => _name; set => Set(ref _name, value); }
    private string _path = "";
    public string Path { get => _path; set => Set(ref _path, value); }
    public FileKind Kind { get; set; }
    public DateTime Added { get; set; } = DateTime.Now;
    public bool IsLink { get; set; }
    /// <summary>When true this entry references a file/folder at its original location
    /// (e.g. on a network drive) instead of an imported copy under the AA data folder.
    /// Opening it launches the live file so edits save straight back to the source.
    /// Such paths are never copied, normalized, or rewritten by the data store.</summary>
    public bool LinkInPlace { get; set; }
    /// <summary>Optional Item IDs (Equipment/Task/Procedure) this file is linked to.</summary>
    public ObservableCollection<Guid> LinkedItemIds { get; set; } = new();

    /// <summary>Human-readable origin shown in the file bank: a live in-place reference,
    /// an imported copy, or a web link.</summary>
    [JsonIgnore]
    public string SourceLabel => IsLink ? "Web link" : LinkInPlace ? "Live" : "Copy";
}

public class Container : NotifyBase
{
    public Guid Id { get; set; } = Guid.NewGuid();
    /// <summary>XAML serialized FlowDocument contents. When <see cref="IsLocked"/> is true and the
    /// app session has not unlocked it, this holds an encrypted blob prefixed with "enc:".</summary>
    private string _richTextXaml = "";
    public string RichTextXaml { get => _richTextXaml; set => Set(ref _richTextXaml, value); }
    public ObservableCollection<FileItem> Files { get; set; } = new();
    /// <summary>Container IDs explicitly linked to share files.</summary>
    public ObservableCollection<Guid> SharedWithContainerIds { get; set; } = new();
    /// <summary>When true the rich-text body is password-protected. The stored
    /// <see cref="RichTextXaml"/> is an encrypted blob ("enc:..."); the file bank stays usable.</summary>
    private bool _isLocked;
    public bool IsLocked { get => _isLocked; set => Set(ref _isLocked, value); }
}

public enum ItemKind { Equipment, Task, Procedure, Vessel }

/// <summary>Anything that can be tagged as a schedulable "Job" with an approximate duration and
/// a (drag-and-drop assigned) start time. Implemented by TaskItem (incl. subtasks) and ChecklistStep.</summary>
public interface IJob
{
    bool IsJob { get; set; }
    /// <summary>Approximate duration in minutes.</summary>
    int DurationMinutes { get; set; }
    /// <summary>When this job is placed on the planner (null = unscheduled).</summary>
    DateTime? ScheduledStart { get; set; }
    /// <summary>Display name for the planner.</summary>
    string JobName { get; }
    Guid Id { get; }
}

public abstract class HierarchyItem : NotifyBase
{
    public Guid Id { get; set; } = Guid.NewGuid();
    private string _name = "";
    public string Name { get => _name; set => Set(ref _name, value); }
    private string _description = "";
    public string Description { get => _description; set => Set(ref _description, value); }
    public Container Container { get; set; } = new();
    public abstract ItemKind Kind { get; }
    /// <summary>Cross-cutting relationships by Id.</summary>
    public ObservableCollection<Guid> RelatedIds { get; set; } = new();
    /// <summary>Free-form tags (Obsidian-style) for filtering, search and quick navigation.</summary>
    public ObservableCollection<string> Tags { get; set; } = new();
    /// <summary>Optional sidebar group this item belongs to. Null = ungrouped.</summary>
    private Guid? _groupId;
    public Guid? GroupId { get => _groupId; set => Set(ref _groupId, value); }

    // ---- Per-item password lock (custom password + optional hint) ----
    // Any Equipment/Task/Procedure/Vessel can be locked with its own password; the app master
    // password ("redemption") always unlocks. LockHash/LockSalt are PBKDF2-SHA256 (see
    // AA.Services.ItemLockService). The lock gates the whole details pane in the UI; it does not
    // encrypt the stored data. Unlocked state lives only in memory for the running session.
    public string? LockHash { get; set; }
    public string? LockSalt { get; set; }
    /// <summary>Optional hint shown to anyone on the lock screen (never the password itself).</summary>
    public string? LockHint { get; set; }
    /// <summary>True when this item carries its own password lock.</summary>
    [JsonIgnore] public bool IsLockProtected => !string.IsNullOrEmpty(LockHash) && !string.IsNullOrEmpty(LockSalt);
}

/// <summary>Sidebar grouping bucket. Items reference a group by Id; the group's Kind
/// constrains which sidebar tab it shows up under.</summary>
public class ItemGroup : NotifyBase
{
    public Guid Id { get; set; } = Guid.NewGuid();
    public ItemKind Kind { get; set; }
    private string _name = "";
    public string Name { get => _name; set => Set(ref _name, value); }
    public bool Expanded { get; set; } = true;
}

public class Equipment : HierarchyItem
{
    [JsonIgnore] public override ItemKind Kind => ItemKind.Equipment;
    public ObservableCollection<Guid> ProcedureIds { get; set; } = new();
    public ObservableCollection<Guid> TaskIds { get; set; } = new();
    public ObservableCollection<Component> Components { get; set; } = new();
}

public class Component : NotifyBase
{
    public Guid Id { get; set; } = Guid.NewGuid();
    private string _name = "";
    public string Name { get => _name; set => Set(ref _name, value); }
    private string _notes = "";
    public string Notes { get => _notes; set => Set(ref _notes, value); }
    /// <summary>Per-component rich-text + file-bank container. Loaded only when the user
    /// opens the component editor, so thousands of components stay cheap to list.</summary>
    public Container Container { get; set; } = new();
}

public enum RecurrenceKind { None, Daily, Weekly, Monthly, Yearly }

/// <summary>Workflow status used by the Kanban board. Named WorkStatus (not TaskStatus)
/// to avoid clashing with System.Threading.Tasks.TaskStatus.</summary>
public enum WorkStatus { Todo, InProgress, Blocked, Done }

public class TaskItem : HierarchyItem, IJob
{
    [JsonIgnore] public override ItemKind Kind => ItemKind.Task;
    private DateTime? _deadline;
    public DateTime? Deadline { get => _deadline; set => Set(ref _deadline, value); }

    private bool _isJob;
    public bool IsJob { get => _isJob; set => Set(ref _isJob, value); }
    private int _durationMinutes = 60;
    public int DurationMinutes { get => _durationMinutes; set => Set(ref _durationMinutes, value); }
    private DateTime? _scheduledStart;
    public DateTime? ScheduledStart { get => _scheduledStart; set => Set(ref _scheduledStart, value); }
    [JsonIgnore] public string JobName => Name;
    private RecurrenceKind _recurrence;
    public RecurrenceKind Recurrence { get => _recurrence; set => Set(ref _recurrence, value); }
    private bool _isComplete;
    public bool IsComplete
    {
        get => _isComplete;
        set
        {
            if (!Set(ref _isComplete, value)) return;
            // Keep Status in sync: completing => Done; un-completing a Done task => Todo.
            // The other setter no-ops when already consistent, so this never recurses.
            if (value && _status != WorkStatus.Done) Status = WorkStatus.Done;
            else if (!value && _status == WorkStatus.Done) Status = WorkStatus.Todo;
        }
    }
    private WorkStatus _status = WorkStatus.Todo;
    /// <summary>Kanban workflow status. Stays in sync with <see cref="IsComplete"/>:
    /// setting Done marks the task complete; any other status clears completion.</summary>
    public WorkStatus Status
    {
        get => _status;
        set
        {
            if (!Set(ref _status, value)) return;
            var done = value == WorkStatus.Done;
            if (_isComplete != done) IsComplete = done;
        }
    }
    public ObservableCollection<TaskItem> Subtasks { get; set; } = new();
}

public class Procedure : HierarchyItem, IJob
{
    [JsonIgnore] public override ItemKind Kind => ItemKind.Procedure;
    public ObservableCollection<ChecklistStep> Steps { get; set; } = new();

    /// <summary>Optional deadline (like a Task's), so procedures can be scheduled/tracked too.</summary>
    private DateTime? _deadline;
    public DateTime? Deadline { get => _deadline; set => Set(ref _deadline, value); }

    /// <summary>Recurrence for the procedure (like a Task's) — None / Daily / Weekly / Monthly / Yearly.</summary>
    private RecurrenceKind _recurrence;
    public RecurrenceKind Recurrence { get => _recurrence; set => Set(ref _recurrence, value); }

    /// <summary>Workflow status for the procedure (like a Task's) — Todo / InProgress / Blocked / Done.</summary>
    private WorkStatus _status = WorkStatus.Todo;
    public WorkStatus Status { get => _status; set => Set(ref _status, value); }

    private bool _isJob;
    public bool IsJob { get => _isJob; set => Set(ref _isJob, value); }
    private int _durationMinutes = 60;
    public int DurationMinutes { get => _durationMinutes; set => Set(ref _durationMinutes, value); }
    private DateTime? _scheduledStart;
    public DateTime? ScheduledStart { get => _scheduledStart; set => Set(ref _scheduledStart, value); }
    [JsonIgnore] public string JobName => Name;
}

public class Vessel : HierarchyItem
{
    [JsonIgnore] public override ItemKind Kind => ItemKind.Vessel;
    /// <summary>Free-form, per-vessel dashboard of resizable Quick Cards (the vessel's first screen).</summary>
    public ObservableCollection<QuickCard> QuickCards { get; set; } = new();
    /// <summary>Shippalm work orders (recurring maintenance jobs) imported for this ship, keyed by
    /// <see cref="ShipJob.JobNo"/>. Per-ship so each vessel owns its own PMS data and notify choices.</summary>
    public ObservableCollection<ShipJob> Jobs { get; set; } = new();
    /// <summary>Master switch for this ship's work-order notifications (shown inside the vessel's
    /// Work Orders tab). When off, no job on this ship raises a notification regardless of its
    /// individual <see cref="ShipJob.Notify"/> flag. Defaults on for legacy data.</summary>
    private bool _notificationsEnabled = true;
    public bool NotificationsEnabled { get => _notificationsEnabled; set => Set(ref _notificationsEnabled, value); }
}

/// <summary>One Shippalm work order (a recurring maintenance job) imported for a vessel from the
/// "Work Order List" export. Keyed by <see cref="JobNo"/> (the Shippalm "No."). The <see cref="DueDate"/>
/// drives notifications; <see cref="Notify"/> is the per-job choice of whether it raises them.</summary>
public class ShipJob : NotifyBase
{
    /// <summary>Shippalm "No." — the primary key, e.g. "ARA.22.3120".</summary>
    public string JobNo { get; set; } = "";
    private string _title = "";
    public string Title { get => _title; set => Set(ref _title, value); }
    public string WorkPlanNo { get; set; } = "";
    public string Status { get; set; } = "";            // Work Order Status (e.g. Execution)
    public string ClassCode { get; set; } = "";
    public string Category { get; set; } = "";          // Work Order Category Code (ROUTINE / CBM)
    public string ResponsibleRank { get; set; } = "";
    public string FunctionNo { get; set; } = "";
    public string FunctionDescription { get; set; } = "";
    public string Interval { get; set; } = "";          // e.g. "64,000 H" / "60M"
    public string DueStatus { get; set; } = "";         // e.g. "in Window"
    public string DueDate { get; set; } = "";           // yyyy-MM-dd (converted from the Excel serial)
    public string FinishedDate { get; set; } = "";
    public string LastDoneDate { get; set; } = "";
    public int OverdueDays { get; set; }
    private bool _notify;
    /// <summary>Whether this recurring job raises due/overdue notifications (chosen per job, per ship).</summary>
    public bool Notify { get => _notify; set => Set(ref _notify, value); }
    public string ImportedAt { get; set; } = "";

    [JsonIgnore] public DateTime? DueDateValue => CrewMember.ParseDate(DueDate);

    /// <summary>Whole days from <paramref name="today"/> until the job is due (negative = overdue),
    /// or null when there's no valid due date.</summary>
    public int? DaysUntilDue(DateTime today)
    {
        var d = DueDateValue;
        return d == null ? null : (int)(d.Value.Date - today.Date).TotalDays;
    }

    /// <summary>Copy all fields from <paramref name="o"/> into this job (used to update an existing
    /// record in place on re-import, avoiding an O(n) collection replace per row).</summary>
    public void CopyFrom(ShipJob o)
    {
        JobNo = o.JobNo; Title = o.Title; WorkPlanNo = o.WorkPlanNo; Status = o.Status;
        ClassCode = o.ClassCode; Category = o.Category; ResponsibleRank = o.ResponsibleRank;
        FunctionNo = o.FunctionNo; FunctionDescription = o.FunctionDescription; Interval = o.Interval;
        DueStatus = o.DueStatus; DueDate = o.DueDate; FinishedDate = o.FinishedDate;
        LastDoneDate = o.LastDoneDate; OverdueDays = o.OverdueDays; Notify = o.Notify;
        ImportedAt = o.ImportedAt;
    }
}

/// <summary>A resizable, colour/icon-customizable shortcut tile on a vessel's Quick Cards screen.
/// Opens a file (imported copy), a file/folder at its original location (link in place), or a URL.</summary>
public class QuickCard : NotifyBase
{
    public Guid Id { get; set; } = Guid.NewGuid();
    private string _title = "";
    public string Title { get => _title; set => Set(ref _title, value); }
    /// <summary>Imported-copy relative path ("files/..."), an absolute in-place path, or a URL.</summary>
    private string _target = "";
    public string Target { get => _target; set => Set(ref _target, value); }
    /// <summary>True when <see cref="Target"/> is a web link (URL).</summary>
    public bool IsLink { get; set; }
    /// <summary>True when <see cref="Target"/> references a file/folder at its original location
    /// (e.g. on a network drive) rather than an imported copy.</summary>
    public bool LinkInPlace { get; set; }
    /// <summary>True when the target is a folder (opens in Explorer).</summary>
    public bool IsFolder { get; set; }
    private string _icon = "⚓";
    public string Icon { get => _icon; set => Set(ref _icon, value); }
    /// <summary>Card background colour as a hex string (#AARRGGBB / #RRGGBB).</summary>
    private string _color = "#FF1E88E5";
    public string Color { get => _color; set => Set(ref _color, value); }
    public double X { get; set; } = 24;
    public double Y { get; set; } = 24;
    public double Width { get; set; } = 180;
    public double Height { get; set; } = 120;

    public QuickCard Clone() => new()
    {
        Id = Id, Title = Title, Target = Target, IsLink = IsLink, LinkInPlace = LinkInPlace,
        IsFolder = IsFolder, Icon = Icon, Color = Color, X = X, Y = Y, Width = Width, Height = Height
    };

    public void CopyFrom(QuickCard o)
    {
        Title = o.Title; Target = o.Target; IsLink = o.IsLink; LinkInPlace = o.LinkInPlace;
        IsFolder = o.IsFolder; Icon = o.Icon; Color = o.Color; X = o.X; Y = o.Y; Width = o.Width; Height = o.Height;
    }
}

public class ChecklistStep : NotifyBase, IJob
{
    public Guid Id { get; set; } = Guid.NewGuid();
    private string _title = "";
    public string Title { get => _title; set => Set(ref _title, value); }
    private bool _done;
    public bool Done { get => _done; set => Set(ref _done, value); }
    /// <summary>Optional per-step deadline — lets a checklist step behave like a task subtask,
    /// appearing in the Calendar and the floating due-dates window with its own due date.</summary>
    private DateTime? _deadline;
    public DateTime? Deadline { get => _deadline; set => Set(ref _deadline, value); }

    private bool _isJob;
    public bool IsJob { get => _isJob; set => Set(ref _isJob, value); }
    private int _durationMinutes = 60;
    public int DurationMinutes { get => _durationMinutes; set => Set(ref _durationMinutes, value); }
    private DateTime? _scheduledStart;
    public DateTime? ScheduledStart { get => _scheduledStart; set => Set(ref _scheduledStart, value); }
    [JsonIgnore] public string JobName => Title;
    /// <summary>Tasks that this step adds (by Task Id).</summary>
    public ObservableCollection<Guid> TaskIds { get; set; } = new();
    /// <summary>Equipment that this step references.</summary>
    public ObservableCollection<Guid> EquipmentIds { get; set; } = new();
    /// <summary>Per-step rich-text + file-bank container. Loaded only when the user
    /// opens the step editor, so procedures with many steps stay cheap to list.</summary>
    public Container Container { get; set; } = new();
}

/// <summary>One item inside a reusable saved checklist. A "full copy" — carries the title, estimated
/// duration, schedulable flag, and a full rich-text + file-bank <see cref="Container"/> (notes/files),
/// but NOT a deadline or done state (those are per-instance, set after the template is applied).</summary>
public class ChecklistTemplateItem : NotifyBase
{
    private string _title = "";
    public string Title { get => _title; set => Set(ref _title, value); }
    private int _durationMinutes = 60;
    public int DurationMinutes { get => _durationMinutes; set => Set(ref _durationMinutes, value); }
    private bool _isJob;
    public bool IsJob { get => _isJob; set => Set(ref _isJob, value); }
    /// <summary>Copied rich-text body + file bank (notes and files) from the source item.</summary>
    public Container Container { get; set; } = new();
}

/// <summary>A named, reusable checklist saved to the database. Can be applied over and over to any
/// checklist builder — procedure steps, task subtasks, or a crew member's checklist.</summary>
public class ChecklistTemplate : NotifyBase
{
    public Guid Id { get; set; } = Guid.NewGuid();
    private string _name = "";
    public string Name { get => _name; set => Set(ref _name, value); }
    public ObservableCollection<ChecklistTemplateItem> Items { get; set; } = new();
    public DateTime CreatedUtc { get; set; } = DateTime.UtcNow;
    /// <summary>Optional List Group this saved list belongs to (null = ungrouped).</summary>
    private Guid? _groupId;
    public Guid? GroupId { get => _groupId; set => Set(ref _groupId, value); }
    [JsonIgnore] public string Display => $"{(_name.Length > 0 ? _name : "(unnamed)")}  ·  {Items.Count} item{(Items.Count == 1 ? "" : "s")}";
}

/// <summary>A named group that bundles one or more saved checklists together in the Saved Lists tab.
/// Purely organisational — a saved list references its group by <see cref="ChecklistTemplate.GroupId"/>.</summary>
public class ListGroup : NotifyBase
{
    public Guid Id { get; set; } = Guid.NewGuid();
    private string _name = "";
    public string Name { get => _name; set => Set(ref _name, value); }
    public DateTime CreatedUtc { get; set; } = DateTime.UtcNow;
}

public class AppData
{
    public ObservableCollection<Equipment> Equipment { get; set; } = new();
    public ObservableCollection<TaskItem> Tasks { get; set; } = new();
    public ObservableCollection<Procedure> Procedures { get; set; } = new();
    public ObservableCollection<Vessel> Vessels { get; set; } = new();
    /// <summary>Sidebar groups across all kinds; filtered per page by <see cref="ItemGroup.Kind"/>.</summary>
    public ObservableCollection<ItemGroup> Groups { get; set; } = new();
    /// <summary>Crew members imported from COMPAS, kept as info cards. Contract expiries are
    /// tracked from each member's <see cref="CrewMember.SignOffDate"/>.</summary>
    public ObservableCollection<CrewMember> Crew { get; set; } = new();
    /// <summary>Append-only activity log of entries added/removed, timestamped in UTC.</summary>
    public ObservableCollection<LogEntry> Log { get; set; } = new();
    /// <summary>Reusable saved checklists, applicable to any checklist builder (procedure steps,
    /// task subtasks, crew checklists).</summary>
    public ObservableCollection<ChecklistTemplate> ChecklistTemplates { get; set; } = new();
    /// <summary>Groups that bundle saved checklists together in the Saved Lists tab.</summary>
    public ObservableCollection<ListGroup> ListGroups { get; set; } = new();
    public UiState Ui { get; set; } = new();
    /// <summary>Wall-clock time this database was last saved by the user. Stamped by
    /// <see cref="AA.Services.AppRepository.Save"/>; used to warn when an imported file is
    /// older than the data already on disk. Null on legacy databases (treated as unknown/old).</summary>
    public DateTime? LastModified { get; set; }
}

/// <summary>One activity-log record: an entry added or removed, stamped in UTC.</summary>
public class LogEntry
{
    public DateTime TimestampUtc { get; set; } = DateTime.UtcNow;
    public string Action { get; set; } = "";   // "Added" / "Removed"
    public string Kind { get; set; } = "";      // "Task" / "Procedure" / "Equipment/Area" / "Vessel" / "Subtask" / ...
    public string Name { get; set; } = "";
    public string Detail { get; set; } = "";    // optional extra context (e.g. parent name)

    [JsonIgnore] public string TimeUtc => TimestampUtc.ToString("yyyy-MM-dd HH:mm:ss 'UTC'");
    [JsonIgnore] public string TimeLocal => TimestampUtc.ToLocalTime().ToString("yyyy-MM-dd HH:mm:ss");
}

public class UiState
{
    public double? WindowLeft { get; set; }
    public double? WindowTop { get; set; }
    public double? WindowWidth { get; set; }
    public double? WindowHeight { get; set; }
    public string? WindowState { get; set; }
    public int SelectedMainTabIndex { get; set; }
    public Guid? SelectedEquipmentId { get; set; }
    public Guid? SelectedTaskId { get; set; }
    public Guid? SelectedProcedureId { get; set; }
    public Guid? SelectedVesselId { get; set; }
    public DateTime? CalendarSelectedDate { get; set; }
    public string? CalendarViewMode { get; set; }
    /// <summary>Persisted font size for the calendar/schedule list (A- / A+ stepper).</summary>
    public double? CalendarFontScale { get; set; }
    /// <summary>Whether the keyboard-shortcuts reminder strip at the bottom of the main window is shown.</summary>
    public bool ShowShortcutBar { get; set; } = true;
    /// <summary>Custom main-tab header colours, keyed by tab name (e.g. "TabTasks"); value is a hex
    /// colour (#RRGGBB / #AARRGGBB). Absent = the default theme colour.</summary>
    public Dictionary<string, string> TabColors { get; set; } = new();
    /// <summary>Persisted size of the floating due-dates window (so a resize sticks across sessions).</summary>
    public double? DueWindowWidth { get; set; }
    public double? DueWindowHeight { get; set; }
    public Guid? MapFocusedItemId { get; set; }
    /// <summary>Per-kind "sort alphabetically" toggle for the sidebar list.</summary>
    public Dictionary<string, bool> SortAZ { get; set; } = new();
    /// <summary>Sidebar group expanded/collapsed state, keyed by "kind|groupName".
    /// Missing entries are treated as expanded (default).</summary>
    public Dictionary<string, bool> GroupExpanded { get; set; } = new();
}
