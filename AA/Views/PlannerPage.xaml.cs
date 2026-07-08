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
    private List<IJob> _jobs = new();
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

    /// <summary>Rebuild just the (searchable) unscheduled-jobs side list from the current job set.</summary>
    private void RefreshUnscheduled()
    {
        var q = _jobSearch.Trim();
        UnscheduledList.ItemsSource = _jobs
            .Where(j => j.ScheduledStart == null)
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

    public void Refresh()
    {
        if (_repo == null) return;
        _jobs = _repo.AllJobs().ToList();

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
        GridHost.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        GridHost.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });

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

            LayoutDayBlocks(canvas, _jobs.Where(j => j.ScheduledStart?.Date == day).ToList(), dayW, day);

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
        Grid.SetRow(sv, 1);
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
                foreach (var j in _jobs.Where(x => x.ScheduledStart?.Date == date).OrderBy(x => x.ScheduledStart!.Value))
                    list.Children.Add(MakeChip(j));
                dock.Children.Add(new ScrollViewer { Content = list, VerticalScrollBarVisibility = ScrollBarVisibility.Auto });

                cell.Child = dock;
                Grid.SetRow(cell, w + 1); Grid.SetColumn(cell, dow);
                GridHost.Children.Add(cell);
            }
        }
    }

    private Border MakeChip(IJob j)
    {
        bool done = j is TaskItem t && t.IsComplete;
        var chip = new Border
        {
            Background = done ? BlockDoneBrush : BlockBrush,
            CornerRadius = new CornerRadius(3),
            Margin = new Thickness(0, 2, 0, 0),
            Padding = new Thickness(4, 1, 4, 1),
            Cursor = Cursors.Hand,
            ToolTip = $"{j.JobName}\n{j.ScheduledStart:HH:mm} ({DurFmt(j.DurationMinutes)})"
        };
        chip.Child = new TextBlock
        {
            Text = $"{j.ScheduledStart:HH:mm} {j.JobName}",
            Foreground = Brushes.White,
            FontSize = 11,
            TextTrimming = TextTrimming.CharacterEllipsis
        };
        AttachDrag(chip, j);
        return chip;
    }

    private static string DurFmt(int minutes)
    {
        if (minutes < 60) return $"{minutes}m";
        int h = minutes / 60, m = minutes % 60;
        return m == 0 ? $"{h}h" : $"{h}h {m}m";
    }

    // ---- Drag & drop ----
    private void AttachDrag(FrameworkElement el, IJob job)
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
            StartDrag(el, job);
        };
    }

    private static void StartDrag(DependencyObject src, IJob job)
    {
        var data = new DataObject();
        data.SetData("AAJob", job);
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
        Save();
    }

    private void MonthCell_Drop(object sender, DragEventArgs e)
    {
        if (_repo == null || sender is not Border b || b.Tag is not DateTime date) return;
        if (e.Data.GetData("AAJob") is not IJob job) return;
        // Keep the existing time-of-day if any; otherwise default to 09:00.
        var tod = job.ScheduledStart?.TimeOfDay ?? TimeSpan.FromHours(9);
        job.ScheduledStart = date.Add(tod);
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

    private static T? FindAncestor<T>(DependencyObject? d) where T : DependencyObject
    {
        while (d != null && d is not T) d = VisualTreeHelper.GetParent(d);
        return d as T;
    }

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
