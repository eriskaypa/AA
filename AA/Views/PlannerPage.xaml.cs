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

public partial class PlannerPage : UserControl
{
    private AppRepository? _repo;
    private DateTime _anchor = DateTime.Today;
    private List<IJob> _jobs = new();      // IsJob items — the draggable "unscheduled" pool
    private List<IJob> _placed = new();     // everything with a when (scheduled time OR a due date)
    private Point _dragStart;
    private string _jobSearch = "";

    private const double HourHeight = 46;
    private const double GutterWidth = 52;
    private const int DayStartHour = 0;
    private const int DayEndHour = 24;
    private const int SnapMin = 15;

    private static readonly Brush BlockBrush = Frozen("#FF1E88E5");
    private static readonly Brush BlockDoneBrush = Frozen("#FF6B7785");
    private static readonly Brush LineBrush = Frozen("#22808080");

    public PlannerPage() { InitializeComponent(); }

    public void Init(AppRepository repo)
    {
        _repo = repo;
        _anchor = DateTime.Today;
        Refresh();
    }

    private static Brush Frozen(string hex)
    {
        var b = new SolidColorBrush((Color)ColorConverter.ConvertFromString(hex));
        b.Freeze();
        return b;
    }

    private string Mode => RbWeek.IsChecked == true ? "Week" : RbMonth.IsChecked == true ? "Month" : "Day";

    // Every task (incl. nested subtasks), procedure, procedure step and crew checklist step — so the
    // planner can place anything that has a due date, not just IsJob items dragged onto the grid.
    private IEnumerable<IJob> AllSchedulable()
    {
        if (_repo == null) yield break;
        foreach (var t in _repo.Data.Tasks) foreach (var x in FlattenTasks(t)) yield return x;
        foreach (var p in _repo.Data.Procedures) { yield return p; foreach (var s in p.Steps) yield return s; }
        foreach (var c in _repo.Data.Crew) foreach (var s in c.Checklist) yield return s;
    }
    private static IEnumerable<IJob> FlattenTasks(TaskItem t)
    {
        yield return t;
        foreach (var st in t.Subtasks) foreach (var x in FlattenTasks(st)) yield return x;
    }
    private static DateTime? DeadlineOf(IJob j) => j switch
    { TaskItem t => t.Deadline, Procedure p => p.Deadline, ChecklistStep s => s.Deadline, _ => null };
    /// <summary>Optional working-range start — only tasks are rangeable; everything else is a point item.</summary>
    private static DateTime? RangeStartOf(IJob j) => j is TaskItem t ? t.RangeStart : null;
    /// <summary>Where an item sits on the planner: its scheduled time if any, else its due date.</summary>
    private static DateTime? WhenOf(IJob j) => j.ScheduledStart ?? DeadlineOf(j);

    /// <summary>The inclusive day-span a due-only item covers: [start..end] where end = deadline and
    /// start = range start (clamped ≤ end), else the deadline itself (a single-day point). Null when undated.</summary>
    private static (DateTime start, DateTime end)? DueSpan(IJob j)
    {
        if (DeadlineOf(j) is not DateTime d) return null;
        var end = d.Date;
        var rs = RangeStartOf(j);
        var start = rs is DateTime s && s.Date <= end ? s.Date : end;
        return (start, end);
    }

    /// <summary>Rebuild the (searchable) unscheduled-jobs side list — IsJob items that have neither a
    /// scheduled time nor a due date (so they still need placing).</summary>
    private void RefreshUnscheduled()
    {
        var q = _jobSearch.Trim();
        UnscheduledList.ItemsSource = _jobs
            .Where(j => j.ScheduledStart == null && DeadlineOf(j) == null)
            .Where(j => q.Length == 0 || (j.JobName ?? "").Contains(q, StringComparison.OrdinalIgnoreCase))
            .Select(j => new JobRow(j))
            .ToList();
    }

    private void JobSearch_Changed(object sender, TextChangedEventArgs e)
    {
        _jobSearch = JobSearchBox.Text ?? "";
        RefreshUnscheduled();
    }

    private void View_Changed(object sender, RoutedEventArgs e) => Refresh();
    private void Today_Click(object sender, RoutedEventArgs e) { _anchor = DateTime.Today; Refresh(); }
    private void Prev_Click(object sender, RoutedEventArgs e) { _anchor = Step(-1); Refresh(); }
    private void Next_Click(object sender, RoutedEventArgs e) { _anchor = Step(1); Refresh(); }
    private DateTime Step(int dir) => Mode switch
    {
        "Week" => _anchor.AddDays(7 * dir),
        "Month" => _anchor.AddMonths(dir),
        _ => _anchor.AddDays(dir),
    };

    private void FromSavedList_Click(object sender, RoutedEventArgs e)
    {
        if (_repo == null) return;
        var created = SavedListPicker.PickAndAddTasks(_repo, Window.GetWindow(this));
        if (created.Count > 0) Refresh();
    }

    public void Refresh()
    {
        if (_repo == null) return;
        _jobs = _repo.AllJobs().ToList();
        // Anything with a scheduled time or a due date is placed on the calendar.
        _placed = AllSchedulable().Where(j => WhenOf(j) != null).ToList();

        RefreshUnscheduled();

        GridHost.Children.Clear();
        GridHost.RowDefinitions.Clear();
        GridHost.ColumnDefinitions.Clear();

        switch (Mode)
        {
            case "Week":
                var start = _anchor.Date.AddDays(-(int)_anchor.DayOfWeek);
                RangeLabel.Text = $"Week of {start:yyyy-MM-dd}";
                BuildTimeGrid(Enumerable.Range(0, 7).Select(i => start.AddDays(i)).ToList());
                break;
            case "Month":
                RangeLabel.Text = _anchor.ToString("MMMM yyyy");
                BuildMonth();
                break;
            default:
                RangeLabel.Text = _anchor.ToString("dddd, yyyy-MM-dd");
                BuildTimeGrid(new List<DateTime> { _anchor.Date });
                break;
        }
    }

    // ---- Day / Week time grid ----
    private void BuildTimeGrid(IReadOnlyList<DateTime> days)
    {
        GridHost.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });   // day-name header
        GridHost.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });   // all-day (no-time) strip
        GridHost.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) }); // hour grid

        double dayW = days.Count == 1 ? 700 : 132;
        double totalH = (DayEndHour - DayStartHour) * HourHeight;

        // Header row (sticky): blank gutter + day names.
        var header = new Grid();
        header.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(GutterWidth) });
        foreach (var _ in days) header.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(dayW) });
        for (int i = 0; i < days.Count; i++)
        {
            var d = days[i];
            var tb = new TextBlock
            {
                Text = days.Count == 1 ? d.ToString("dddd, MMM d") : d.ToString("ddd\nMMM d"),
                TextAlignment = TextAlignment.Center,
                Padding = new Thickness(2, 4, 2, 4),
                FontWeight = d.Date == DateTime.Today ? FontWeights.Bold : FontWeights.Normal,
                Foreground = d.Date == DateTime.Today ? (Brush)FindResource("Accent") : (Brush)FindResource("Fg")
            };
            Grid.SetColumn(tb, i + 1);
            header.Children.Add(tb);
        }
        Grid.SetRow(header, 0);
        GridHost.Children.Add(header);

        // All-day strip: items with a due date but no time-of-day, chronologically stacked per day.
        var allDay = new Grid { Background = (Brush)FindResource("PanelAlt") };
        allDay.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(GutterWidth) });
        foreach (var _ in days) allDay.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(dayW) });
        allDay.Children.Add(new TextBlock
        {
            Text = "due",
            FontSize = 10,
            Foreground = (Brush)FindResource("Muted"),
            HorizontalAlignment = HorizontalAlignment.Right,
            VerticalAlignment = VerticalAlignment.Top,
            Margin = new Thickness(0, 5, 6, 0)
        });
        for (int i = 0; i < days.Count; i++)
        {
            var day = days[i].Date;
            var stack = new StackPanel { Margin = new Thickness(3, 3, 3, 3) };
            // Every due-only item whose working range covers this day (a point item covers only its deadline).
            var due = _placed
                .Where(j => j.ScheduledStart == null && DueSpan(j) is { } sp && day >= sp.start && day <= sp.end)
                .OrderBy(j => DueSpan(j)!.Value.start)
                .ThenBy(j => j.JobName ?? "", StringComparer.OrdinalIgnoreCase)
                .ToList();
            foreach (var j in due)
            {
                var sp = DueSpan(j)!.Value;
                stack.Children.Add(MakeAllDayChip(j, day, isEnd: day == sp.end, isStart: day == sp.start, multi: sp.start < sp.end));
            }
            var sv2 = new ScrollViewer
            {
                Content = stack,
                VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
                HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled,
                MaxHeight = 108
            };
            Grid.SetColumn(sv2, i + 1);
            allDay.Children.Add(sv2);
        }
        var allDayBorder = new Border
        {
            Child = allDay,
            BorderBrush = LineBrush,
            BorderThickness = new Thickness(0, 0, 0, 1)
        };
        Grid.SetRow(allDayBorder, 1);
        GridHost.Children.Add(allDayBorder);

        // Body: scrollable hour grid.
        var body = new Grid();
        body.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(GutterWidth) });
        foreach (var _ in days) body.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(dayW) });

        var gutter = new Canvas { Height = totalH };
        for (int h = DayStartHour; h <= DayEndHour; h++)
        {
            var lbl = new TextBlock { Text = $"{h:00}:00", FontSize = 11, Foreground = (Brush)FindResource("Muted") };
            Canvas.SetTop(lbl, (h - DayStartHour) * HourHeight - 7);
            Canvas.SetLeft(lbl, 6);
            gutter.Children.Add(lbl);
        }
        Grid.SetColumn(gutter, 0);
        body.Children.Add(gutter);

        for (int i = 0; i < days.Count; i++)
        {
            var day = days[i].Date;
            var canvas = new Canvas
            {
                Height = totalH,
                Width = dayW,
                Background = day == DateTime.Today ? (Brush)FindResource("PanelAlt") : Brushes.Transparent,
                Tag = day,
                AllowDrop = true
            };
            canvas.DragOver += Grid_DragOver;
            canvas.Drop += DayCanvas_Drop;

            for (int h = DayStartHour; h <= DayEndHour; h++)
            {
                var line = new Border { Height = 1, Width = dayW, Background = LineBrush };
                Canvas.SetTop(line, (h - DayStartHour) * HourHeight);
                canvas.Children.Add(line);
            }
            // vertical separator
            var sep = new Border { Width = 1, Height = totalH, Background = LineBrush };
            Canvas.SetLeft(sep, dayW - 1);
            canvas.Children.Add(sep);

            LayoutDayBlocks(canvas, _placed.Where(j => j.ScheduledStart?.Date == day).ToList(), dayW, day);

            Grid.SetColumn(canvas, i + 1);
            body.Children.Add(canvas);
        }

        var sv = new ScrollViewer
        {
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
            HorizontalScrollBarVisibility = ScrollBarVisibility.Auto,
            Content = body
        };
        sv.Loaded += (_, _) => sv.ScrollToVerticalOffset(7 * HourHeight);
        Grid.SetRow(sv, 2);
        GridHost.Children.Add(sv);
    }

    private static DateTime JobEnd(IJob j) => j.ScheduledStart!.Value.AddMinutes(Math.Max(15, j.DurationMinutes));

    private void LayoutDayBlocks(Canvas canvas, List<IJob> jobs, double dayW, DateTime day)
    {
        var items = jobs.Where(j => j.ScheduledStart.HasValue).OrderBy(j => j.ScheduledStart!.Value).ToList();
        int i = 0;
        while (i < items.Count)
        {
            // Build a cluster of mutually/transitively overlapping jobs.
            var cluster = new List<IJob> { items[i] };
            var clusterEnd = JobEnd(items[i]);
            int j = i + 1;
            while (j < items.Count && items[j].ScheduledStart!.Value < clusterEnd)
            {
                cluster.Add(items[j]);
                if (JobEnd(items[j]) > clusterEnd) clusterEnd = JobEnd(items[j]);
                j++;
            }

            // Greedy column assignment within the cluster.
            var colEnds = new List<DateTime>();
            var colOf = new Dictionary<IJob, int>();
            foreach (var it in cluster)
            {
                int c = 0;
                for (; c < colEnds.Count; c++)
                    if (colEnds[c] <= it.ScheduledStart!.Value) { colEnds[c] = JobEnd(it); break; }
                if (c == colEnds.Count) colEnds.Add(JobEnd(it));
                colOf[it] = c;
            }
            int cols = Math.Max(1, colEnds.Count);
            double w = (dayW - 2) / cols;
            foreach (var it in cluster) AddBlock(canvas, it, day, colOf[it], w);

            i = j;
        }
    }

    private void AddBlock(Canvas canvas, IJob j, DateTime day, int col, double w)
    {
        var start = j.ScheduledStart!.Value;
        double top = (start - day).TotalMinutes / 60.0 * HourHeight;
        double h = Math.Max(20, Math.Max(15, j.DurationMinutes) / 60.0 * HourHeight);
        bool done = j is TaskItem t && t.IsComplete;

        var border = new Border
        {
            Width = Math.Max(24, w - 3),
            Height = h,
            Background = done ? BlockDoneBrush : BlockBrush,
            CornerRadius = new CornerRadius(4),
            ClipToBounds = true,
            Cursor = Cursors.Hand,
            ToolTip = $"{j.JobName}\n{start:HH:mm}–{JobEnd(j):HH:mm} ({DurFmt(j.DurationMinutes)})\nDrag to move • double-click to edit"
        };
        var sp = new StackPanel { Margin = new Thickness(5, 3, 5, 3) };
        sp.Children.Add(new TextBlock
        {
            Text = j.JobName,
            Foreground = Brushes.White,
            FontWeight = FontWeights.Bold,
            FontSize = 12,
            TextTrimming = TextTrimming.CharacterEllipsis
        });
        if (h >= 34)
            sp.Children.Add(new TextBlock
            {
                Text = $"{start:HH:mm}–{JobEnd(j):HH:mm}  ({DurFmt(j.DurationMinutes)})",
                Foreground = Brushes.White,
                FontSize = 10,
                Opacity = 0.9
            });
        border.Child = sp;
        Canvas.SetTop(border, top);
        Canvas.SetLeft(border, col * w + 1);
        AttachDrag(border, j);
        canvas.Children.Add(border);
    }

    // ---- Month ----
    private void BuildMonth()
    {
        var first = new DateTime(_anchor.Year, _anchor.Month, 1);
        var start = first.AddDays(-(int)first.DayOfWeek); // grid starts on Sunday

        for (int c = 0; c < 7; c++) GridHost.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        GridHost.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        for (int r = 0; r < 6; r++) GridHost.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });

        var dayNames = new[] { "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" };
        for (int c = 0; c < 7; c++)
        {
            var tb = new TextBlock { Text = dayNames[c], FontWeight = FontWeights.Bold, TextAlignment = TextAlignment.Center, Padding = new Thickness(4) };
            Grid.SetRow(tb, 0); Grid.SetColumn(tb, c);
            GridHost.Children.Add(tb);
        }

        for (int w = 0; w < 6; w++)
        {
            for (int dow = 0; dow < 7; dow++)
            {
                var date = start.AddDays(w * 7 + dow);
                bool inMonth = date.Month == _anchor.Month;
                var cell = new Border
                {
                    BorderBrush = (Brush)FindResource("BorderB"),
                    BorderThickness = new Thickness(0.5),
                    Background = date == DateTime.Today ? (Brush)FindResource("PanelAlt") : Brushes.Transparent,
                    AllowDrop = true,
                    Tag = date
                };
                cell.DragOver += Grid_DragOver;
                cell.Drop += MonthCell_Drop;

                var dock = new DockPanel { Margin = new Thickness(3) };
                dock.Children.Add(new TextBlock
                {
                    Text = date.Day.ToString(),
                    FontWeight = date == DateTime.Today ? FontWeights.Bold : FontWeights.Normal,
                    Foreground = inMonth ? (Brush)FindResource("Fg") : (Brush)FindResource("Muted"),
                    Opacity = inMonth ? 1 : 0.5
                });
                DockPanel.SetDock(dock.Children[0], Dock.Top);

                var list = new StackPanel();
                // Timed items land on their scheduled day; due-only items appear on every day their range covers.
                var cellDate = date;
                foreach (var j in _placed.Where(x => x.ScheduledStart != null
                                 ? x.ScheduledStart.Value.Date == cellDate
                                 : DueSpan(x) is { } sp && cellDate >= sp.start && cellDate <= sp.end)
                             .OrderBy(x => x.ScheduledStart == null ? 1 : 0)          // timed first
                             .ThenBy(x => x.ScheduledStart ?? DateTime.MinValue)
                             .ThenBy(x => x.JobName ?? "", StringComparer.OrdinalIgnoreCase))
                {
                    if (j.ScheduledStart == null && DueSpan(j) is { } s)
                        list.Children.Add(MakeChip(j, cellDate, isEnd: cellDate == s.end, isStart: cellDate == s.start, multi: s.start < s.end));
                    else
                        list.Children.Add(MakeChip(j, cellDate, false, false, false));
                }
                dock.Children.Add(new ScrollViewer { Content = list, VerticalScrollBarVisibility = ScrollBarVisibility.Auto });

                cell.Child = dock;
                Grid.SetRow(cell, w + 1); Grid.SetColumn(cell, dow);
                GridHost.Children.Add(cell);
            }
        }
    }

    private Border MakeChip(IJob j, DateTime date, bool isEnd, bool isStart, bool multi)
    {
        bool done = j is TaskItem t && t.IsComplete;
        bool timed = j.ScheduledStart != null;
        // On non-deadline days of a multi-day range the chip is de-emphasised; the deadline day stays solid.
        bool ghost = multi && !isEnd;
        var chip = new Border
        {
            Background = done ? BlockDoneBrush : BlockBrush,
            CornerRadius = new CornerRadius(3),
            Margin = new Thickness(0, 2, 0, 0),
            Padding = new Thickness(4, 1, 4, 1),
            Cursor = Cursors.Hand,
            Opacity = ghost ? 0.55 : 1.0,
            ToolTip = ChipTip(j, timed, multi)
        };
        chip.Child = new TextBlock
        {
            Text = timed ? $"{j.ScheduledStart:HH:mm} {j.JobName}" : $"{RangeGlyph(isStart, isEnd, multi)}{j.JobName}",
            Foreground = Brushes.White,
            FontSize = 11,
            FontWeight = multi && isEnd ? FontWeights.Bold : FontWeights.Normal,
            TextTrimming = TextTrimming.CharacterEllipsis
        };
        AttachDrag(chip, j, j.ScheduledStart == null ? date.Date : null);
        return chip;
    }

    // A no-time (due-date-only) chip for the day/week all-day strip. Wraps so nothing is clipped.
    private Border MakeAllDayChip(IJob j, DateTime day, bool isEnd, bool isStart, bool multi)
    {
        bool done = j is TaskItem t && t.IsComplete;
        bool ghost = multi && !isEnd;
        var chip = new Border
        {
            Background = done ? BlockDoneBrush : BlockBrush,
            CornerRadius = new CornerRadius(3),
            Margin = new Thickness(0, 0, 0, 3),
            Padding = new Thickness(6, 2, 6, 2),
            Cursor = Cursors.Hand,
            Opacity = ghost ? 0.6 : 1.0,
            ToolTip = ChipTip(j, false, multi)
        };
        chip.Child = new TextBlock
        {
            Text = $"{RangeGlyph(isStart, isEnd, multi)}{j.JobName}",
            Foreground = Brushes.White,
            FontSize = 11,
            FontWeight = multi && isEnd ? FontWeights.Bold : FontWeights.Normal,
            TextWrapping = TextWrapping.Wrap
        };
        AttachDrag(chip, j, day.Date);
        return chip;
    }

    // Leading glyph that shows where a day sits in a multi-day range: ⚑ on the deadline, ▸ on the start,
    // · on middle days. Point/single-day items get a plain bullet, exactly as before.
    private static string RangeGlyph(bool isStart, bool isEnd, bool multi)
    {
        if (!multi) return "• ";
        if (isEnd) return "⚑ ";
        if (isStart) return "▸ ";
        return "· ";
    }

    private string ChipTip(IJob j, bool timed, bool multi)
    {
        if (timed) return $"{j.JobName}\n{j.ScheduledStart:HH:mm} ({DurFmt(j.DurationMinutes)})";
        if (multi && j is TaskItem t && t.RangeStart is DateTime s && t.Deadline is DateTime d)
        {
            int m = (int)(d.Date - s.Date).TotalDays + 1;
            return $"{j.JobName}\n{s:yyyy-MM-dd} → {d:yyyy-MM-dd}  ({m} days)\nDrag in Month to move the whole range • double-click to edit";
        }
        return $"{j.JobName}\ndue {DeadlineOf(j):yyyy-MM-dd} (no time)\nDrag onto the grid to give it a time • double-click to edit";
    }

    private static string DurFmt(int minutes)
    {
        if (minutes < 60) return $"{minutes}m";
        int h = minutes / 60, m = minutes % 60;
        return m == 0 ? $"{h}h" : $"{h}h {m}m";
    }

    private static void SetDeadlineOf(IJob j, DateTime? v)
    {
        switch (j)
        {
            case TaskItem t: t.Deadline = v; break;
            case Procedure p: p.Deadline = v; break;
            case ChecklistStep s: s.Deadline = v; break;
        }
    }

    // ---- Drag & drop ----
    // anchorDay = the calendar day the dragged chip represents (a month/all-day chip); lets a drop compute
    // how far a ranged item's whole window should slide. Null for timed hour-grid blocks.
    private void AttachDrag(FrameworkElement el, IJob job, DateTime? anchorDay = null)
    {
        el.Tag = job;
        el.PreviewMouseLeftButtonDown += (s, e) =>
        {
            _dragStart = e.GetPosition(null);
            if (e.ClickCount == 2) { OpenJobEditor(job); e.Handled = true; }
        };
        el.PreviewMouseMove += (s, e) =>
        {
            if (e.LeftButton != MouseButtonState.Pressed) return;
            var p = e.GetPosition(null);
            if (Math.Abs(p.X - _dragStart.X) < SystemParameters.MinimumHorizontalDragDistance &&
                Math.Abs(p.Y - _dragStart.Y) < SystemParameters.MinimumVerticalDragDistance) return;
            StartDrag(el, job, anchorDay);
        };
    }

    private static void StartDrag(DependencyObject src, IJob job, DateTime? anchorDay = null)
    {
        var data = new DataObject();
        data.SetData("AAJob", job);
        if (anchorDay is DateTime a) data.SetData("AAJobDay", a);
        DragDrop.DoDragDrop(src, data, DragDropEffects.Move);
    }

    private void Grid_DragOver(object sender, DragEventArgs e)
    {
        e.Effects = e.Data.GetDataPresent("AAJob") ? DragDropEffects.Move : DragDropEffects.None;
        e.Handled = true;
    }

    private void DayCanvas_Drop(object sender, DragEventArgs e)
    {
        if (_repo == null || sender is not Canvas cv || cv.Tag is not DateTime day) return;
        if (e.Data.GetData("AAJob") is not IJob job) return;
        double y = e.GetPosition(cv).Y;
        int mins = (int)Math.Round(y / HourHeight * 60.0 / SnapMin) * SnapMin;
        mins = Math.Max(0, Math.Min((DayEndHour * 60) - SnapMin, mins));
        job.ScheduledStart = day.AddMinutes(mins);
        // Dropping a ranged task onto a day outside its window extends the window to include that day,
        // so scheduling never contradicts the range (start <= this day <= deadline).
        if (job is TaskItem t && t.RangeStart is DateTime rs)
        {
            if (t.Deadline is DateTime d && day.Date > d.Date) t.Deadline = day.Date;
            if (day.Date < rs.Date) t.RangeStart = day.Date;
        }
        Save();
    }

    private void MonthCell_Drop(object sender, DragEventArgs e)
    {
        if (_repo == null || sender is not Border b || b.Tag is not DateTime date) return;
        if (e.Data.GetData("AAJob") is not IJob job) return;

        if (job.ScheduledStart != null)
        {
            // A timed item: keep its time-of-day, just move it to the dropped day.
            job.ScheduledStart = date.Add(job.ScheduledStart.Value.TimeOfDay);
        }
        else if (job is TaskItem t && t.RangeStart is DateTime rs && t.Deadline is DateTime dl)
        {
            // A due-only task that has a range: slide the WHOLE window (length preserved) so RangeStart and
            // Deadline never get stranded on opposite sides of the dropped day.
            if (e.Data.GetData("AAJobDay") is DateTime anchor)
            {
                var delta = date.Date - anchor.Date;
                t.RangeStart = rs.Date + delta;
                t.Deadline = dl.Date + delta;
            }
            else
            {
                // No anchor (shouldn't happen for a chip): put the deadline on the dropped day, keep length.
                var len = dl.Date - rs.Date;
                t.Deadline = date.Date;
                t.RangeStart = date.Date - len;
            }
        }
        else
        {
            // A due-only point item (no range): month-drag moves its due date to the dropped day.
            SetDeadlineOf(job, date.Date);
        }
        Save();
    }

    private void Unscheduled_Drop(object sender, DragEventArgs e)
    {
        if (_repo == null) return;
        if (e.Data.GetData("AAJob") is not IJob job) return;
        job.ScheduledStart = null;
        Save();
    }

    private void Job_PreviewDown(object sender, MouseButtonEventArgs e) => _dragStart = e.GetPosition(null);

    private void Job_PreviewMove(object sender, MouseEventArgs e)
    {
        if (e.LeftButton != MouseButtonState.Pressed) return;
        var p = e.GetPosition(null);
        if (Math.Abs(p.X - _dragStart.X) < SystemParameters.MinimumHorizontalDragDistance &&
            Math.Abs(p.Y - _dragStart.Y) < SystemParameters.MinimumVerticalDragDistance) return;
        var item = FindAncestor<ListBoxItem>(e.OriginalSource as DependencyObject);
        if (item?.DataContext is JobRow row) StartDrag(item, row.Job);
    }

    private void Unscheduled_DoubleClick(object sender, MouseButtonEventArgs e)
    {
        if (UnscheduledList.SelectedItem is JobRow row) OpenJobEditor(row.Job);
    }

    private void Save()
    {
        _repo!.MarkDirty();
        _repo.FlushIfDirty();
        Refresh();
    }

    private void OpenJobEditor(IJob job)
    {
        if (_repo == null) return;
        switch (job)
        {
            case TaskItem t:
                new SubtaskEditorWindow(t, _repo) { Owner = Window.GetWindow(this) }.ShowDialog();
                break;
            case ChecklistStep s:
                new ChecklistStepEditorWindow(s, _repo) { Owner = Window.GetWindow(this) }.ShowDialog();
                break;
        }
        _repo.FlushIfDirty();
        Refresh();
    }

    private static T? FindAncestor<T>(DependencyObject? d) where T : DependencyObject => UiTree.FindAncestor<T>(d);

    private sealed class JobRow
    {
        public IJob Job { get; }
        public string Display { get; }
        public JobRow(IJob j)
        {
            Job = j;
            Display = $"{j.JobName}   ·   {DurFmt(j.DurationMinutes)}";
        }
        public override string ToString() => Display;
    }
}
