using System;
using System.Collections.Generic;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using AA.Models;
using AA.Services;

namespace AA.Views;

/// <summary>Small always-on-top window listing everything overdue (past deadline, not done) plus what's
/// due today and tomorrow — tasks, subtasks, procedures, and their checklist/crew steps — so nothing
/// urgent drops off the radar.</summary>
public partial class FloatingTasksWindow : Window
{
    private AppRepository? _repo;
    private readonly Action<HierarchyItem>? _navigate;
    private readonly Action<CrewMember>? _navigateCrew;

    private static readonly Brush TaskBrush = Frozen("#FFFFB74D");   // amber
    private static readonly Brush ProcBrush = Frozen("#FF2E9E5B");   // green
    private static readonly Brush JobBrush  = Frozen("#FF4FC3F7");   // blue — scheduled Planner jobs
    private static readonly Brush CrewBrush = Frozen("#FF9C6ADE");   // purple — crew checklist items
    private static readonly Brush OverdueBrush = Frozen("#FFE05252"); // red — past-due, not done
    private static readonly Brush MutedBrush = Frozen("#FF8A8A8A");
    private static SolidColorBrush Frozen(string hex)
    { var b = new SolidColorBrush((Color)ColorConverter.ConvertFromString(hex)); b.Freeze(); return b; }

    public FloatingTasksWindow(AppRepository repo, Action<HierarchyItem>? navigate, Action<CrewMember>? navigateCrew = null)
    {
        InitializeComponent();
        _navigate = navigate;
        _navigateCrew = navigateCrew;
        SetRepo(repo);
        Loaded += OnLoaded;
        Closed += OnClosed;
    }

    private void OnClosed(object? sender, EventArgs e)
    {
        if (_repo != null) _repo.Saved -= OnDataSaved;
    }

    /// <summary>Point the window at the current repository (re-pointed after a data reload/import).</summary>
    public void SetRepo(AppRepository repo)
    {
        if (_repo != null) _repo.Saved -= OnDataSaved;
        _repo = repo;
        _repo.Saved += OnDataSaved;
        if (IsLoaded) Refresh();
    }

    private void OnDataSaved()
    {
        // Saves happen on the UI thread; keep the list live as tasks/jobs change.
        if (IsVisible) Refresh();
    }

    private void OnLoaded(object? sender, RoutedEventArgs e)
    {
        // Restore a previously-chosen size (the window is user-resizable via the corner grip).
        if (_repo?.Data.Ui.DueWindowWidth is double w && w >= MinWidth) Width = w;
        if (_repo?.Data.Ui.DueWindowHeight is double h && h >= MinHeight) Height = h;
        // Park it at the bottom-right of the working area on first show.
        var wa = SystemParameters.WorkArea;
        Left = wa.Right - Width - 16;
        Top = wa.Bottom - Height - 16;
        Refresh();
    }

    private void Header_Drag(object sender, MouseButtonEventArgs e)
    {
        if (e.ChangedButton == MouseButton.Left) DragMove();
    }

    private void Refresh_Click(object sender, RoutedEventArgs e) => Refresh();
    private void Close_Click(object sender, RoutedEventArgs e) => Close();

    private void ResizeGrip_DragDelta(object sender, System.Windows.Controls.Primitives.DragDeltaEventArgs e)
    {
        Width = Math.Max(MinWidth, Width + e.HorizontalChange);
        Height = Math.Max(MinHeight, Height + e.VerticalChange);
        // Persist the size as it changes (MarkDirty here means the app's normal/close-time save captures
        // it — writing only in OnClosed would miss the debounce window during app shutdown).
        if (_repo != null)
        {
            _repo.Data.Ui.DueWindowWidth = Width;
            _repo.Data.Ui.DueWindowHeight = Height;
            _repo.MarkDirty();
        }
    }

    private sealed class DueItem
    {
        public string Icon = "";
        public string Title = "";
        public string Sub = "";
        public Brush Accent = MutedBrush;
        public HierarchyItem? Nav;
        /// <summary>Custom click action (used for crew items, which aren't HierarchyItems).
        /// Takes precedence over <see cref="Nav"/> when set.</summary>
        public Action? OnClick;
        /// <summary>Ordering key for the Overdue section (oldest deadline first); unused elsewhere.</summary>
        public DateTime SortDate = DateTime.MaxValue;
        /// <summary>The completable model behind this row (TaskItem / Procedure / ChecklistStep), so the row
        /// gets a "done" checkbox. Null for rows that aren't directly completable.</summary>
        public object? Item;
    }

    public void Refresh()
    {
        Host.Children.Clear();
        if (_repo == null) return;
        var today = DateTime.Today;
        var tomorrow = today.AddDays(1);

        var overdueItems = CollectOverdue();
        var todayItems = Collect(today);
        var tomorrowItems = Collect(tomorrow);

        HeaderSub.Text = (overdueItems.Count > 0 ? $"{overdueItems.Count} overdue  ·  " : "")
            + $"Today {today:ddd, dd MMM}  ·  Tomorrow {tomorrow:ddd, dd MMM}";

        if (overdueItems.Count > 0) AddSection("OVERDUE", today, overdueItems);
        AddSection("TODAY", today, todayItems);
        AddSection("TOMORROW", tomorrow, tomorrowItems);

        if (overdueItems.Count == 0 && todayItems.Count == 0 && tomorrowItems.Count == 0)
            Host.Children.Add(new TextBlock
            {
                Text = "Nothing overdue, or due today or tomorrow 🎉",
                Foreground = MutedBrush, TextAlignment = TextAlignment.Center,
                Margin = new Thickness(0, 24, 0, 0), TextWrapping = TextWrapping.Wrap
            });
    }

    private List<DueItem> Collect(DateTime day)
    {
        var items = new List<DueItem>();
        if (_repo == null) return items;
        var seen = new HashSet<Guid>();   // dedupe: an item shown by deadline isn't re-shown as a scheduled job

        // Tasks + subtasks (recursive) with a deadline on this day, not completed.
        foreach (var t in _repo.Data.Tasks)
            CollectTask(t, t, day, items, seen);

        // Procedures with a deadline on this day, plus their checklist steps (each step acts like a
        // subtask with its own deadline).
        foreach (var p in _repo.Data.Procedures)
        {
            if (p.Status != WorkStatus.Done && p.Deadline?.Date == day && seen.Add(p.Id))
                items.Add(new DueItem { Icon = "📋", Title = p.Name, Sub = "Procedure", Accent = ProcBrush, Nav = p, Item = p });
            foreach (var s in p.Steps)
                if (!s.Done && s.Deadline?.Date == day && seen.Add(s.Id))
                    items.Add(new DueItem { Icon = "☑", Title = s.Title, Sub = $"Checklist step · {p.Name}", Accent = ProcBrush, Nav = p, Item = s });
        }

        // Crew members' personal checklist items with a deadline on this day (not done). Clicking a row
        // jumps to that crew member (crew aren't HierarchyItems, so they use a custom click action).
        foreach (var c in _repo.Data.Crew)
        {
            var member = c;
            foreach (var s in member.Checklist)
                if (!s.Done && s.Deadline?.Date == day && seen.Add(s.Id))
                    items.Add(new DueItem
                    {
                        Icon = "🧑‍✈️",
                        Title = s.Title,
                        Sub = $"Crew checklist · {(member.FullName.Length > 0 ? member.FullName : "(unnamed)")}",
                        Accent = CrewBrush,
                        OnClick = _navigateCrew != null ? () => _navigateCrew(member) : null,
                        Item = s
                    });
        }

        // Jobs scheduled (in the Planner) to start on this day — so a job you drop on today's grid
        // shows up here too. Skip completed ones and dedupe against anything already listed by deadline.
        foreach (var j in _repo.AllJobs())
        {
            if (j.ScheduledStart?.Date != day || JobDone(j) || !seen.Add(j.Id)) continue;
            var (nav, onClick, ctx) = JobNav(j);
            items.Add(new DueItem
            {
                Icon = "🕒",
                Title = j.JobName,
                Sub = $"Scheduled {j.ScheduledStart:HH:mm}" + (ctx.Length > 0 ? $" · {ctx}" : ""),
                Accent = JobBrush,
                Nav = nav,
                OnClick = onClick,
                Item = j
            });
        }

        // Note: Shippalm work-order notifications are intentionally NOT shown here — they stay inside
        // each vessel's own Work Orders tab (per-ship notifications with a per-ship on/off switch).
        return items;
    }

    private void CollectTask(TaskItem owner, TaskItem t, DateTime day, List<DueItem> items, HashSet<Guid> seen)
    {
        // A ranged task shows on every day its working window covers, not only the deadline day.
        if (!t.IsComplete && t.CoversDay(day) && seen.Add(t.Id))
        {
            bool isSub = !ReferenceEquals(owner, t);
            string kind = isSub ? $"Subtask · {owner.Name}" : "Task";
            if (t.HasRange)
            {
                string where = day.Date == t.Deadline!.Value.Date ? "ends today"
                    : day.Date == t.RangeStart!.Value.Date ? "starts today" : "ongoing";
                kind += $" · {where}";
            }
            items.Add(new DueItem
            {
                Icon = isSub ? "↳" : "✓",
                Title = t.Name,
                Sub = kind,
                Accent = TaskBrush,
                Nav = owner,
                Item = t
            });
        }
        foreach (var st in t.Subtasks) CollectTask(owner, st, day, items, seen);
    }

    /// <summary>Everything past its deadline and not yet done — tasks/subtasks, procedures, procedure and
    /// crew checklist steps — so overdue work never silently drops off the window. Oldest first.</summary>
    private List<DueItem> CollectOverdue()
    {
        var items = new List<DueItem>();
        if (_repo == null) return items;
        var today = DateTime.Today;
        var seen = new HashSet<Guid>();

        foreach (var t in _repo.Data.Tasks) CollectOverdueTask(t, t, today, items, seen);

        foreach (var p in _repo.Data.Procedures)
        {
            if (p.Status != WorkStatus.Done && p.Deadline is DateTime pd && pd.Date < today && seen.Add(p.Id))
                items.Add(MkOverdue("📋", p.Name, "Procedure", pd, today, p, item: p));
            foreach (var s in p.Steps)
                if (!s.Done && s.Deadline is DateTime sd && sd.Date < today && seen.Add(s.Id))
                    items.Add(MkOverdue("☑", s.Title, $"Checklist step · {p.Name}", sd, today, p, item: s));
        }

        foreach (var c in _repo.Data.Crew)
        {
            var member = c;
            foreach (var s in member.Checklist)
                if (!s.Done && s.Deadline is DateTime sd && sd.Date < today && seen.Add(s.Id))
                    items.Add(MkOverdue("🧑‍✈️", s.Title,
                        $"Crew checklist · {(member.FullName.Length > 0 ? member.FullName : "(unnamed)")}", sd, today,
                        null, _navigateCrew != null ? () => _navigateCrew(member) : null, item: s));
        }

        return items.OrderBy(i => i.SortDate).ToList();
    }

    private void CollectOverdueTask(TaskItem owner, TaskItem t, DateTime today, List<DueItem> items, HashSet<Guid> seen)
    {
        // Deadline (the range END) is what makes a task overdue — a task still inside its working range
        // isn't overdue and shows under TODAY instead.
        if (!t.IsComplete && t.Deadline is DateTime d && d.Date < today && seen.Add(t.Id))
        {
            bool isSub = !ReferenceEquals(owner, t);
            items.Add(MkOverdue(isSub ? "↳" : "✓", t.Name, isSub ? $"Subtask · {owner.Name}" : "Task", d, today, owner, item: t));
        }
        foreach (var st in t.Subtasks) CollectOverdueTask(owner, st, today, items, seen);
    }

    private static DueItem MkOverdue(string icon, string title, string kind, DateTime due, DateTime today,
        HierarchyItem? nav, Action? onClick = null, object? item = null)
    {
        int days = (int)(today - due.Date).TotalDays;
        return new DueItem
        {
            Icon = icon,
            Title = title,
            Sub = $"{kind} · {days}d overdue (was due {due:ddd, dd MMM})",
            Accent = OverdueBrush,
            Nav = nav,
            OnClick = onClick,
            SortDate = due.Date,
            Item = item
        };
    }

    private static bool JobDone(IJob j) => j switch
    {
        TaskItem t => t.IsComplete,
        ChecklistStep s => s.Done,
        Procedure p => p.Status == WorkStatus.Done,
        _ => false
    };

    /// <summary>Navigation target + short context label for a scheduled job (a task, a procedure, or a
    /// checklist step — whose owning procedure OR crew member is looked up so the row can still navigate).
    /// Crew-owned steps navigate via <paramref name="onClick"/> since crew aren't HierarchyItems.</summary>
    private (HierarchyItem? nav, Action? onClick, string ctx) JobNav(IJob j)
    {
        switch (j)
        {
            case TaskItem t: return (t, null, "Task job");
            case Procedure p: return (p, null, "Procedure job");
            case ChecklistStep s:
                var owner = _repo?.Data.Procedures.FirstOrDefault(pr => pr.Steps.Contains(s));
                if (owner != null) return (owner, null, $"Step job · {owner.Name}");
                var member = _repo?.Data.Crew.FirstOrDefault(c => c.Checklist.Contains(s));
                if (member != null)
                    return (null, _navigateCrew != null ? () => _navigateCrew(member) : null,
                        $"Crew step job · {(member.FullName.Length > 0 ? member.FullName : "(unnamed)")}");
                return (null, null, "Step job");
            default: return (null, null, "");
        }
    }

    private void AddSection(string label, DateTime day, List<DueItem> items)
    {
        var hdr = new TextBlock
        {
            Text = $"{label}   ({items.Count})",
            FontWeight = FontWeights.Bold, FontSize = 12,
            Foreground = label == "OVERDUE" ? OverdueBrush : MutedBrush,
            // The first section (Overdue when present, else Today) hugs the top; later sections get a gap.
            Margin = new Thickness(2, Host.Children.Count == 0 ? 0 : 14, 0, 6)
        };
        Host.Children.Add(hdr);

        if (items.Count == 0)
        {
            Host.Children.Add(new TextBlock { Text = "— nothing —", Foreground = MutedBrush, FontSize = 11, Margin = new Thickness(6, 0, 0, 0) });
            return;
        }

        foreach (var it in items)
            Host.Children.Add(BuildRow(it));
    }

    private UIElement BuildRow(DueItem it)
    {
        var border = new Border
        {
            Background = (Brush)FindResource("PanelAlt"),
            BorderBrush = it.Accent,
            BorderThickness = new Thickness(4, 0, 0, 0),
            CornerRadius = new CornerRadius(4),
            Padding = new Thickness(8, 6, 8, 6),
            Margin = new Thickness(0, 0, 0, 5),
            Cursor = (it.Nav != null || it.OnClick != null) ? Cursors.Hand : Cursors.Arrow
        };
        var dock = new DockPanel();

        // Completable rows get a "done" checkbox — tick it to mark the item complete; it then drops off
        // the window (a done item is no longer overdue or due).
        if (it.Item != null)
        {
            var chk = new CheckBox
            {
                IsChecked = IsItemDone(it.Item),
                VerticalAlignment = VerticalAlignment.Top,
                Margin = new Thickness(0, 1, 6, 0),
                ToolTip = "Mark done"
            };
            chk.Checked += (_, _) => CompleteItem(it.Item, true);
            chk.Unchecked += (_, _) => CompleteItem(it.Item, false);
            DockPanel.SetDock(chk, Dock.Left);
            dock.Children.Add(chk);
        }

        dock.Children.Add(new TextBlock
        {
            Text = it.Icon, FontSize = 15, Width = 24, VerticalAlignment = VerticalAlignment.Top,
            Foreground = it.Accent, TextAlignment = TextAlignment.Center
        });
        var sp = new StackPanel();
        sp.Children.Add(new TextBlock
        {
            Text = it.Title, FontWeight = FontWeights.SemiBold, TextWrapping = TextWrapping.Wrap,
            Foreground = (Brush)FindResource("Fg")
        });
        sp.Children.Add(new TextBlock
        {
            Text = it.Sub, FontSize = 11, TextWrapping = TextWrapping.Wrap,
            Foreground = MutedBrush
        });
        dock.Children.Add(sp);
        border.Child = dock;

        if (it.OnClick != null || it.Nav != null)
            border.MouseLeftButtonUp += (_, e) =>
            {
                // A click on the row's checkbox marks it done — it must not also navigate.
                if (e.OriginalSource is DependencyObject src && UiTree.FindAncestor<CheckBox>(src) != null) return;
                if (it.OnClick != null) it.OnClick();
                else _navigate?.Invoke(it.Nav!);
            };
        return border;
    }

    private static bool IsItemDone(object? item) => item switch
    {
        TaskItem t => t.IsComplete,
        Procedure p => p.Status == WorkStatus.Done,
        ChecklistStep s => s.Done,
        _ => false
    };

    /// <summary>Mark the row's underlying item done/undone, persist, and rebuild the list (a completed item
    /// leaves the window). Refresh is deferred so we don't tear down the checkbox from inside its own event.</summary>
    private void CompleteItem(object? item, bool done)
    {
        if (_repo == null || item == null) return;
        if (BatchDone.SetDone(item, done)) { _repo.MarkDirty(); _repo.FlushIfDirty(); }
        Dispatcher.BeginInvoke(new Action(Refresh));
    }
}
