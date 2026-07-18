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

/// <summary>Small always-on-top window listing everything due today and tomorrow — tasks, subtasks,
/// procedures (their deadlines), and notify-enabled Shippalm work orders — so the next two days are
/// visible at a glance.</summary>
public partial class FloatingTasksWindow : Window
{
    private AppRepository? _repo;
    private readonly Action<HierarchyItem>? _navigate;
    private readonly Action<CrewMember>? _navigateCrew;

    private static readonly Brush TaskBrush = Frozen("#FFFFB74D");   // amber
    private static readonly Brush ProcBrush = Frozen("#FF2E9E5B");   // green
    private static readonly Brush JobBrush  = Frozen("#FF4FC3F7");   // blue — scheduled Planner jobs
    private static readonly Brush CrewBrush = Frozen("#FF9C6ADE");   // purple — crew checklist items
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
    }

    public void Refresh()
    {
        Host.Children.Clear();
        if (_repo == null) return;
        var today = DateTime.Today;
        var tomorrow = today.AddDays(1);
        HeaderSub.Text = $"Today {today:ddd, dd MMM}  ·  Tomorrow {tomorrow:ddd, dd MMM}";

        var todayItems = Collect(today);
        var tomorrowItems = Collect(tomorrow);

        AddSection("TODAY", today, todayItems);
        AddSection("TOMORROW", tomorrow, tomorrowItems);

        if (todayItems.Count == 0 && tomorrowItems.Count == 0)
            Host.Children.Add(new TextBlock
            {
                Text = "Nothing due today or tomorrow 🎉",
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
            if (p.Deadline?.Date == day && seen.Add(p.Id))
                items.Add(new DueItem { Icon = "📋", Title = p.Name, Sub = "Procedure", Accent = ProcBrush, Nav = p });
            foreach (var s in p.Steps)
                if (!s.Done && s.Deadline?.Date == day && seen.Add(s.Id))
                    items.Add(new DueItem { Icon = "☑", Title = s.Title, Sub = $"Checklist step · {p.Name}", Accent = ProcBrush, Nav = p });
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
                        OnClick = _navigateCrew != null ? () => _navigateCrew(member) : null
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
                OnClick = onClick
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
                Nav = owner
            });
        }
        foreach (var st in t.Subtasks) CollectTask(owner, st, day, items, seen);
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
            FontWeight = FontWeights.Bold, FontSize = 12, Foreground = MutedBrush,
            Margin = new Thickness(2, label == "TODAY" ? 0 : 14, 0, 6)
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

        if (it.OnClick != null)
            border.MouseLeftButtonUp += (_, _) => it.OnClick();
        else if (it.Nav != null)
            border.MouseLeftButtonUp += (_, _) => { _navigate?.Invoke(it.Nav); };
        return border;
    }
}
